# ApolloTeam — povoa o lab com dados de demonstração para navegar e avaliar o produto.
#
# Rodar:   docker exec apollo-desk-rails bundle exec rails runner /tmp/seed-demo.rb
# Limpar:  docker exec apollo-desk-rails bundle exec rails runner /tmp/limpa-demo.rb
#
# TUDO que este script cria leva additional_attributes['demo'] = true (ou o
# prefixo [demo] no nome, onde o modelo não tem esse campo). É o que permite
# ao limpa-demo apagar com cirurgia em vez de truncar tabela — e é o que
# garante que nenhum dado real seja levado junto quando o lab virar produção.
#
# Os diálogos são de atendimento REAL da Apollo (dúvida de fatura, suporte de
# e-mail, lead de site, reclamação). Dado de demonstração genérico não mostra
# se o produto serve: só conversa parecida com a verdadeira revela se a caixa
# de entrada, os rótulos e a atribuição fazem sentido.

account = Account.first
raise 'Nenhuma conta encontrada — faça o onboarding primeiro.' if account.nil?

admin = User.find_by(email: 'leonardo@apollosolution.com.br') || User.first
raise 'Nenhum usuário encontrado.' if admin.nil?

puts "Conta: #{account.name} (##{account.id}) · admin: #{admin.name}"
DEMO = { 'demo' => true }.freeze

# ── Agentes ──────────────────────────────────────────────────────────────────
# Atribuição só faz sentido com mais de uma pessoa: com um agente só, a coluna
# "Atribuído a" é sempre a mesma e não dá para avaliar o roteamento.
AGENTES = [
  { name: 'Clarice Castelhano', email: 'demo.clarice@apollosolution.com.br' },
  { name: 'Guilherme Barbosa',  email: 'demo.guilherme@apollosolution.com.br' }
].freeze

# O Chatwoot valida senha: mínimo de tamanho + 1 maiúscula + 1 especial.
# `SecureRandom.hex` sozinho (só minúsculas e dígitos) reprova na validação —
# o seed morreu nisso na primeira execução. Estes agentes são só figurantes
# para a demonstração: a senha é aleatória e descartada, ninguém loga com eles.
def senha_aleatoria
  "Ap#{SecureRandom.hex(20)}!9"
end

agentes = AGENTES.map do |a|
  u = User.find_by(email: a[:email])
  if u.nil?
    u = User.create!(name: a[:name], email: a[:email], password: senha_aleatoria,
                     confirmed_at: Time.current)
    puts "  + agente #{a[:name]}"
  end
  AccountUser.find_or_create_by!(account: account, user: u) { |au| au.role = :agent }
  u
end
todos_agentes = [admin] + agentes

# ── Times ────────────────────────────────────────────────────────────────────
TIMES = [
  ['[demo] Suporte',   'Chamados técnicos e incidentes'],
  ['[demo] Comercial', 'Leads, propostas e renovações']
].freeze

times = TIMES.map do |nome, desc|
  # ⚠️ O Chatwoot MINÚSCULIZA o nome do time ao salvar ("[demo] Suporte" vira
  # "[demo] suporte"). Um find_or_create_by pelo nome original nunca encontra o
  # registro que ele mesmo gravou, tenta criar de novo e estoura
  # "Name has already been taken" — o seed morreu exatamente nisso.
  # Por isso a busca é case-insensitive e a criação usa o nome já em minúsculas.
  t = Team.where(account: account).where('lower(name) = ?', nome.downcase).first
  t ||= Team.create!(account: account, name: nome.downcase, description: desc)
  todos_agentes.each { |u| TeamMember.find_or_create_by!(team: t, user: u) }
  t
end

# ── Rótulos ──────────────────────────────────────────────────────────────────
ROTULOS = [
  ['demo-urgente',    'ff6b6b'], ['demo-financeiro', 'f7b731'],
  ['demo-suporte',    '0a7d47'], ['demo-lead',       '2fe68c'],
  ['demo-onboarding', '6b46c1']
].freeze

# ⚠️ Os Label PRECISAM ser criados aqui. O `add_labels` da conversa só grava a
# marcação (acts_as_taggable_on); ele NÃO cria a linha em `labels`, que é o que
# alimenta a lista de rótulos da conta e a barra lateral. Sem este bloco, a
# conversa aparece marcada e a tela de Rótulos fica vazia — foi o que aconteceu.
ROTULOS.each do |titulo, cor|
  Label.find_or_create_by!(account: account, title: titulo) do |l|
    l.color = "##{cor}"
    l.show_on_sidebar = true
  end
end

# ── Caixas de entrada ────────────────────────────────────────────────────────
# Três canais para a barra lateral não ficar com um item só. O canal da Meta
# fica de fora DE PROPÓSITO: exige app no Meta Business e número verificado —
# é a etapa E4, não dá para simular sem mentir sobre o que está funcionando.
# ⚠️ O canal vem num BLOCO, não como argumento. Na primeira versão a chamada
# era caixa(conta, nome, Channel::X.create!(...)) — e Ruby avalia o argumento
# SEMPRE, mesmo quando a caixa já existia e o método ia retornar cedo. Cada
# tentativa deixava um canal órfão no banco, e a segunda execução morria com
# "Email has already been taken" por causa do canal de e-mail duplicado.
def caixa(account, nome)
  inbox = Inbox.find_by(account: account, name: nome)
  return inbox if inbox

  Inbox.create!(account: account, name: nome, channel: yield)
end

widget = caixa(account, '[demo] Site — apollosolution.com.br') do
  Channel::WebWidget.create!(account: account, website_url: 'https://apollosolution.com.br',
                             widget_color: '#0A7D47')
end
email_inbox = caixa(account, '[demo] contato@apollosolution.com.br') do
  Channel::Email.create!(account: account,
                         email: "demo-contato-#{SecureRandom.hex(3)}@apollosolution.com.br",
                         forward_to_email: "demo-#{SecureRandom.hex(4)}@apollosolution.com.br")
end
api_inbox = caixa(account, '[demo] WhatsApp — Comercial') { Channel::Api.create!(account: account, webhook_url: '') }

[widget, email_inbox, api_inbox].each do |i|
  todos_agentes.each { |u| InboxMember.find_or_create_by!(inbox: i, user: u) }
end

# ── Conversas ────────────────────────────────────────────────────────────────
# [quem, telefone, caixa, status, rótulos, agente, dias_atras, [[direção, texto], ...]]
DIALOGOS = [
  ['Marina Alvarenga', '+5511987650001', :api, :open, %w[demo-urgente demo-suporte], 0, 0, [
    [:in,  'Bom dia! O e-mail da nossa equipe parou de chegar desde ontem à noite.'],
    [:out, 'Bom dia, Marina! Já estou olhando. Consegue confirmar se é só o e-mail ou o acesso ao Apollo Cloud também caiu?'],
    [:in,  'Só o e-mail. O Cloud abre normal.'],
    [:out, 'Perfeito, isso ajuda a isolar. Vou verificar a fila de entrega do servidor e te retorno em até 30 minutos.'],
    [:in,  'Obrigada! É urgente porque o financeiro depende disso pro fechamento.']
  ]],
  ['Ricardo Penteado', '+5511987650002', :widget, :open, %w[demo-lead], 1, 0, [
    [:in,  'Oi, vi o site de vocês. Atendem empresa com 40 funcionários?'],
    [:out, 'Olá, Ricardo! Atendemos sim — esse é exatamente o nosso porte típico. Posso entender melhor o que você precisa?'],
    [:in,  'Basicamente e-mail profissional e um lugar pra guardar arquivo que não seja o Drive.'],
    [:out, 'É o combo mais pedido. Consigo te mandar uma proposta hoje ainda. Qual o melhor e-mail?']
  ]],
  ['Juliana Prado', '+5511987650003', :email, :pending, %w[demo-financeiro], 1, 1, [
    [:in,  'Recebi a fatura de agosto com valor diferente do mês passado. Podem verificar?'],
    [:out, 'Oi, Juliana! Verifiquei aqui: em agosto entraram 3 caixas de e-mail novas que foram solicitadas dia 12. A diferença é proporcional a elas.'],
    [:in,  'Ah, faz sentido. Consegue me mandar o detalhamento pra eu repassar pra contabilidade?']
  ]],
  ['Anderson Vasques', '+5511987650004', :api, :resolved, %w[demo-suporte], 0, 3, [
    [:in,  'Não consigo entrar no sistema, diz senha inválida.'],
    [:out, 'Olá, Anderson! Vou disparar um link de redefinição para o seu e-mail corporativo agora.'],
    [:in,  'Chegou, consegui entrar. Valeu!'],
    [:out, 'Ótimo! Vou encerrar o atendimento então. Qualquer coisa é só chamar.']
  ]],
  ['Patrícia Nogueira', '+5511987650005', :widget, :open, %w[demo-onboarding], 1, 1, [
    [:in,  'Terminamos a migração dos arquivos. Falta treinar o time, tem material?'],
    [:out, 'Temos! Mando o guia rápido em PDF e podemos marcar uma call de 40 minutos com a equipe.'],
    [:in,  'A call seria ótima. Quinta de manhã funciona?']
  ]],
  ['Eduardo Sampaio', '+5511987650006', :api, :open, %w[demo-urgente], 0, 0, [
    [:in,  'Pessoal, o site do cliente saiu do ar. Vocês conseguem olhar?'],
    [:out, 'Estou verificando agora, Eduardo.']
  ]],
  ['Camila Rezende', '+5511987650007', :email, :resolved, %w[demo-financeiro], 1, 6, [
    [:in,  'Preciso da nota fiscal de julho para o fechamento.'],
    [:out, 'Segue em anexo, Camila. Qualquer divergência me avisa.'],
    [:in,  'Recebido, obrigada!']
  ]],
  ['Fernando Bittencourt', '+5511987650008', :widget, :pending, %w[demo-lead], 0, 2, [
    [:in,  'Quanto fica pra 12 usuários?'],
    [:out, 'Depende do que entra no pacote. Você precisa só de e-mail ou também de armazenamento e gestão de projetos?'],
    [:in,  'Os três.']
  ]],
  ['Tatiana Muniz', '+5511987650009', :api, :open, %w[demo-suporte demo-onboarding], 1, 0, [
    [:in,  'O celular do meu time não está sincronizando os arquivos.'],
    [:out, 'Oi, Tatiana! É em Android ou iPhone? E o app está atualizado?'],
    [:in,  'iPhone, e acho que não atualizamos faz tempo.'],
    [:out, 'Provavelmente é isso. Pede pra atualizarem e me diz se resolveu.']
  ]],
  ['Marcelo Assunção', '+5511987650010', :email, :open, [], 0, 4, [
    [:in,  'Boa tarde, gostaria de entender melhor a política de backup de vocês.'],
    [:out, 'Boa tarde, Marcelo! Fazemos cópia diária com retenção e uma cópia fora do servidor principal. Posso detalhar por escrito se ajudar.']
  ]]
].freeze

caixas = { widget: widget, email: email_inbox, api: api_inbox }
criadas = 0

DIALOGOS.each do |nome, fone, canal, status, rotulos, idx_agente, dias, mensagens|
  inbox = caixas[canal]
  contato = Contact.find_by(account: account, phone_number: fone)
  contato ||= Contact.create!(
    account: account, name: nome, phone_number: fone,
    email: "#{nome.parameterize}@exemplo.com.br",
    additional_attributes: DEMO.merge('company_name' => 'Empresa Demo', 'city' => 'São Paulo')
  )

  ci = ContactInbox.find_or_create_by!(contact: contato, inbox: inbox) do |x|
    x.source_id = SecureRandom.uuid
  end

  next if Conversation.exists?(contact_inbox_id: ci.id)

  base = dias.days.ago
  conversa = Conversation.create!(
    account: account, inbox: inbox, contact: contato, contact_inbox: ci,
    assignee: todos_agentes[idx_agente], team: times[idx_agente % times.size],
    status: status, additional_attributes: DEMO, created_at: base
  )

  mensagens.each_with_index do |(direcao, texto), i|
    Message.create!(
      account: account, inbox: inbox, conversation: conversa,
      message_type: direcao == :in ? :incoming : :outgoing,
      content: texto,
      sender: direcao == :in ? contato : todos_agentes[idx_agente],
      created_at: base + (i * 7).minutes
    )
  end

  # ⚠️ `update!(labels: [...])` NÃO funciona: a associação é acts_as_taggable_on
  # e espera objetos Tag, então uma lista de String estoura
  # AssociationTypeMismatch. O método da casa é add_labels, que aceita títulos
  # e cria o Label na conta quando falta.
  conversa.add_labels(rotulos) if rotulos.any?
  criadas += 1
end

# ── Cores dos rótulos (agora que o app já os criou) ──────────────────────────
ROTULOS.each do |titulo, cor|
  l = Label.find_by(account: account, title: titulo)
  l&.update!(color: "##{cor}", show_on_sidebar: true)
end

# ── Respostas prontas ────────────────────────────────────────────────────────
PRONTAS = [
  ['demo-ola',     'Olá! Aqui é da Apollo. Como posso ajudar?'],
  ['demo-prazo',   'Estou verificando com o time técnico e retorno em até 30 minutos.'],
  ['demo-encerra', 'Vou encerrar este atendimento. Qualquer coisa, é só chamar por aqui!']
].freeze

PRONTAS.each do |atalho, conteudo|
  CannedResponse.find_or_create_by!(account: account, short_code: atalho) { |c| c.content = conteudo }
end

# ── Conferência pelo BANCO, não pelo exit code ───────────────────────────────
puts
puts '── conferindo ─────────────────────────────'
res = {
  'caixas de entrada' => Inbox.where(account: account).where("name like '[demo]%'").count,
  'contatos'          => Contact.where(account: account).where("additional_attributes->>'demo' = 'true'").count,
  'conversas'         => Conversation.where(account: account).count,
  'mensagens'         => Message.where(account: account).count,
  'rótulos'           => Label.where(account: account).where("title like 'demo-%'").count,
  'times'             => Team.where(account: account).where("name like '[demo]%'").count,
  'respostas prontas' => CannedResponse.where(account: account).where("short_code like 'demo-%'").count
}
res.each { |k, v| puts format('  %-18s %d', k, v) }

abertas = Conversation.where(account: account, status: :open).count
puts
puts "  #{criadas} conversas novas nesta execução · #{abertas} em aberto na caixa"
puts 'OK.' if res['conversas'].positive? && res['mensagens'].positive?
