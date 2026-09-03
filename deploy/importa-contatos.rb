# ApolloDesk — importa contatos de um CSV para UMA empresa, prontos para campanha.
#
# Rodar:
#   docker cp contatos.csv apollo-desk-rails:/tmp/contatos.csv
#   docker cp deploy/importa-contatos.rb apollo-desk-rails:/tmp/
#   docker exec -e CONTA=4 -e CSV=/tmp/contatos.csv -e ROTULOS="clientes-2026" \
#               apollo-desk-rails bundle exec rails runner /tmp/importa-contatos.rb
#
#   CONTA    id da empresa no ApolloDesk (Apollo=1 · Dagostino=4 · CD Tech=5 · TZ=6)
#   CSV      caminho DENTRO do container
#   ROTULOS  rótulos aplicados a TODOS os contatos do arquivo, separados por vírgula
#   ENSAIO=1 só valida e mostra o que faria — não grava nada
#
# CSV esperado (cabeçalho obrigatório, ordem livre, UTF-8):
#   nome,telefone,email,opt_in,rotulos
#   Maria Silva,(17) 99123-4567,maria@x.com,sim,vip;promo-natal
#
#   telefone  qualquer formato brasileiro; vira E.164 (+55DDD9XXXXXXXX)
#   opt_in    "sim" — a pessoa AUTORIZOU receber mensagem. Qualquer outra coisa recusa a linha.
#   rotulos   opcionais, por linha, separados por ";"  (somam-se aos de ROTULOS)
#
# POR QUE ESTE SCRIPT E NÃO A IMPORTAÇÃO NATIVA DO CHATWOOT
# ----------------------------------------------------------
# O Chatwoot importa CSV (DataImport), mas ele:
#   - NÃO normaliza telefone brasileiro: "(17) 99123-4567" é recusado pela
#     validação E.164 (\A\+[1-9]\d{1,14}\z) e a linha some em silêncio;
#   - NÃO sabe o que é opt-in — importa a planilha inteira, e disparar para quem
#     não autorizou é o caminho mais curto para a Meta derrubar o número;
#   - NÃO cria a linha em `labels`: acts_as_taggable marca o contato, mas a tela
#     de Rótulos e a CAMPANHA lêem `account.labels`. Contato rotulado com rótulo
#     que "não existe" = público vazio. (Mesma armadilha do seed-demo.rb.)
#
# A campanha do Chatwoot mira RÓTULO, não lista. Importar sem rotular é importar
# para ninguém.
#
# Conferir o EFEITO, não o exit code: no fim ele relê do banco.

require 'csv'

conta_id = ENV['CONTA'].presence or abort 'ERRO: defina CONTA=<id da empresa>'
csv_path = ENV['CSV'].presence   or abort 'ERRO: defina CSV=/tmp/arquivo.csv'
ensaio   = ENV['ENSAIO'].present?
rotulos_globais = ENV['ROTULOS'].to_s.split(',').map { |r| r.strip.downcase }.reject(&:empty?)

conta = Account.find_by(id: conta_id) or abort "ERRO: empresa ##{conta_id} não existe"
abort "ERRO: arquivo não encontrado: #{csv_path}" unless File.exist?(csv_path)

puts "── importando para: #{conta.name} (##{conta.id})#{ensaio ? '  [ENSAIO — nada será gravado]' : ''} ──"
puts "   rótulos para todos: #{rotulos_globais.empty? ? '(nenhum)' : rotulos_globais.join(', ')}"

# ── Telefone brasileiro → E.164 ────────────────────────────────────────────
# Aceita: (17) 99123-4567 · 17991234567 · +55 17 99123-4567 · 5517991234567 ·
# 017991234567 (zero de operadora). Devolve nil se não fizer sentido.
#
# ⚠️ Celular brasileiro tem 9 dígitos após o DDD e começa com 9. Um número com
# 8 dígitos após o DDD é fixo (WhatsApp Business aceita fixo, mas é raro em
# planilha de cliente) — tratamos como válido, sem inventar o 9.
def e164_br(bruto)
  d = bruto.to_s.gsub(/\D/, '')
  return nil if d.empty?

  d = d.sub(/\A0+/, '')                 # zero de operadora / discagem
  d = d.sub(/\A55/, '') if d.length >= 12 # já veio com o país
  return nil unless d.length.between?(10, 11)

  ddd, numero = d[0, 2], d[2..]
  return nil unless ddd.to_i.between?(11, 99)
  return nil if numero.length == 9 && !numero.start_with?('9')

  "+55#{ddd}#{numero}"
end

def opt_in?(valor)
  %w[sim s yes y true 1 x].include?(valor.to_s.strip.downcase)
end

linhas = CSV.read(csv_path, headers: true, encoding: 'bom|utf-8')
obrig = %w[nome telefone opt_in]
faltam = obrig - linhas.headers.map { |h| h.to_s.strip.downcase }
abort "ERRO: cabeçalho sem as colunas: #{faltam.join(', ')} (tem: #{linhas.headers.join(', ')})" if faltam.any?

stats = Hash.new(0)
recusadas = []
rotulos_usados = Set.new(rotulos_globais)
para_gravar = []

linhas.each_with_index do |l, i|
  n = i + 2 # linha do arquivo, contando o cabeçalho
  nome  = l['nome'].to_s.strip
  fone  = e164_br(l['telefone'])
  email = l['email'].to_s.strip.downcase.presence
  rots  = rotulos_globais + l['rotulos'].to_s.split(';').map { |r| r.strip.downcase }.reject(&:empty?)

  if nome.empty?
    recusadas << "linha #{n}: sem nome"; stats[:sem_nome] += 1; next
  end
  if fone.nil?
    recusadas << "linha #{n}: telefone inválido #{l['telefone'].inspect} (#{nome})"; stats[:telefone_invalido] += 1; next
  end
  unless opt_in?(l['opt_in'])
    # Não é erro de dado, é decisão: sem autorização, não entra. E fica visível.
    recusadas << "linha #{n}: SEM OPT-IN (#{nome}, #{fone})"; stats[:sem_opt_in] += 1; next
  end
  if email && email !~ URI::MailTo::EMAIL_REGEXP
    recusadas << "linha #{n}: e-mail inválido #{email.inspect} (#{nome}) — importado sem e-mail"; stats[:email_ignorado] += 1
    email = nil
  end

  rots.each { |r| rotulos_usados << r }
  para_gravar << { linha: n, nome: nome, fone: fone, email: email, rotulos: rots.uniq }
end

puts
puts "── validação ──────────────────────────────"
puts format('   linhas no arquivo      %d', linhas.size)
puts format('   prontas para importar  %d', para_gravar.size)
puts format('   sem opt-in             %d', stats[:sem_opt_in])
puts format('   telefone inválido      %d', stats[:telefone_invalido])
puts format('   sem nome               %d', stats[:sem_nome])
puts format('   e-mail ignorado        %d', stats[:email_ignorado])
puts format('   rótulos envolvidos     %s', rotulos_usados.to_a.sort.join(', ').presence || '(nenhum)')

if recusadas.any?
  puts
  puts '── recusadas (as 20 primeiras) ────────────'
  recusadas.first(20).each { |r| puts "   #{r}" }
  puts "   … e mais #{recusadas.size - 20}" if recusadas.size > 20
end

if rotulos_usados.empty?
  puts
  puts '⚠️  NENHUM RÓTULO. A campanha de WhatsApp escolhe o público por rótulo —'
  puts '   contatos sem rótulo são invisíveis para ela. Use ROTULOS=... ou a coluna rotulos.'
end

if ensaio
  puts
  puts 'ENSAIO: nada foi gravado.'
  exit(recusadas.any? ? 2 : 0)
end

abort 'ERRO: nada para importar.' if para_gravar.empty?

# ── Gravar ─────────────────────────────────────────────────────────────────
puts
puts '── gravando ───────────────────────────────'

# A linha em `labels` PRECISA existir: é o que a tela de Rótulos e o seletor de
# público da campanha lêem. Título é minusculizado pelo próprio modelo.
rotulos_usados.each do |t|
  Label.find_or_create_by!(account: conta, title: t) { |lb| lb.color = '#2FE68C' }
end

criados = atualizados = 0
para_gravar.each do |c|
  contato = conta.contacts.find_by(phone_number: c[:fone])
  if contato
    contato.update!(name: c[:nome], email: c[:email] || contato.email)
    atualizados += 1
  else
    contato = conta.contacts.create!(name: c[:nome], phone_number: c[:fone], email: c[:email])
    criados += 1
  end
  # add_labels soma aos existentes; não apaga rótulo que o atendente já pôs.
  contato.add_labels(c[:rotulos]) if c[:rotulos].any?
rescue ActiveRecord::RecordInvalid => e
  # E-mail duplicado em outro contato é o caso típico. Não parar o lote por uma linha.
  puts "   linha #{c[:linha]}: NÃO gravado — #{e.message}"
  stats[:falha_gravar] += 1
end

# ── Conferir pelo BANCO ────────────────────────────────────────────────────
puts
puts '── conferindo ─────────────────────────────'
puts format('   criados      %d', criados)
puts format('   atualizados  %d', atualizados)
puts format('   falhas       %d', stats[:falha_gravar])
rotulos_usados.to_a.sort.each do |t|
  existe = Label.exists?(account: conta, title: t)
  n = conta.contacts.tagged_with(t, on: :labels).count
  puts format('   rótulo %-24s linha em labels: %-4s contatos: %d', t, existe ? 'sim' : 'NÃO', n)
end

puts
if stats[:falha_gravar].positive?
  puts "ATENÇÃO: #{stats[:falha_gravar]} linha(s) não gravaram — ver acima."
  exit 1
end
puts "OK: #{criados + atualizados} contato(s) de #{conta.name} prontos para campanha."
