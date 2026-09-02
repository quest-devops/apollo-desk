# ApolloDesk — grava as credenciais do canal da Meta em installation_configs.
#
# Rodar:
#   docker cp deploy/set-meta.rb apollo-desk-rails:/tmp/
#   docker exec apollo-desk-rails bundle exec rails runner /tmp/set-meta.rb
#   docker restart apollo-desk-rails      # o cache do GlobalConfig e por processo
#
# POR QUE ISTO EXISTE — por o valor no .env NAO liga o canal
# ----------------------------------------------------------
# GlobalConfigService.load(chave, padrao) ate cai para o ambiente e se
# auto-grava no banco, MAS so quando alguem chama o servico. A tela do app e
# montada em dashboard_controller com @global_config, que le
# `installation_configs` DIRETO. Entao, com as variaveis no .env e o container
# reiniciado, o front recebe:
#
#   whatsappAppId: ''
#
# e o botao de conectar WhatsApp simplesmente nao abre — SEM ERRO NENHUM. E a
# mesma falha silenciosa do INSTALLATION_NAME (ver set-marca.rb): "esta no
# ambiente" nao e a mesma coisa que "o app enxerga".
#
# ⚠️ WHATSAPP_API_VERSION NAO ENTRA AQUI, de proposito. No v4.17.1 essa chave
# nao esta nem na lista branca GLOBAL_CONFIG_KEYS nem no app_config do
# dashboard_controller — ela sai vazia para o front em QUALQUER instalacao. E
# bug do Chatwoot e e inofensivo, porque o JS cai para v22.0
# (`const version = apiVersion || 'v22.0'` em channels/whatsapp/utils.js).
# Gravar no banco daria a falsa sensacao de ter resolvido: o valor nao chega ao
# front por caminho nenhum.
#
# ⚠️ Nada de valor literal aqui. As credenciais vem do ambiente, que o compose
# carrega de /root/plan-secrets/apollo-desk.env (chmod 600). Segredo nao mora
# em git.

CHAVES = %w[WHATSAPP_APP_ID WHATSAPP_CONFIGURATION_ID WHATSAPP_APP_SECRET].freeze

# Quais podem aparecer em claro no log: as duas primeiras sao identificadores
# publicos (vao no HTML servido ao navegador); a terceira e segredo.
SEGREDOS = %w[WHATSAPP_APP_SECRET].freeze

def mostrar(nome, valor)
  return '(vazio)' if valor.to_s.empty?

  SEGREDOS.include?(nome) ? "[presente, #{valor.length} caracteres]" : valor
end

puts '── credenciais do canal da Meta ───────────'

faltando = CHAVES.reject { |k| ENV[k].to_s.strip.present? }
if faltando.any?
  puts "  ERRO: sem valor no ambiente: #{faltando.join(', ')}"
  puts '  Conferir /root/plan-secrets/apollo-desk.env e o env_file do compose.'
  exit 1
end

CHAVES.each do |nome|
  valor = ENV[nome].strip
  config = InstallationConfig.find_or_initialize_by(name: nome)
  antes = config.value.to_s
  config.value = valor
  config.locked = false
  config.save!
  estado = if antes == valor then 'ja estava'
           elsif antes.empty? then 'GRAVADO (estava vazio)'
           else 'ATUALIZADO'
           end
  puts format('  %-28s %s', nome, estado)
end

GlobalConfig.clear_cache

# ── Conferir o EFEITO, nao o exit code ─────────────────────────────────────
puts
puts '── conferindo pelo BANCO ──────────────────'
erros = CHAVES.reject do |nome|
  lido = GlobalConfig.get(nome)[nome].to_s
  ok = lido == ENV[nome].strip
  puts format('  %-28s %s %s', nome, ok ? 'OK ' : 'ERRO', mostrar(nome, lido))
  ok
end

puts
if erros.any?
  puts "ERRO: #{erros.size} chave(s) nao gravaram."
  exit 1
end
puts "OK: as #{CHAVES.size} chaves estao no banco."
puts
puts 'A conferencia que de fato importa e no HTML servido, depois de REINICIAR:'
puts "  curl -s https://app.apollodesk.com.br/app/login | grep -o \"whatsappAppId: .[^,]*\""
puts 'Se vier vazio ali, o banco estar certo nao adianta nada.'
