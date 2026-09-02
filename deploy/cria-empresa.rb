# ApolloDesk — cria a empresa (account) de um cliente na instância compartilhada.
#
# Rodar:
#   docker cp deploy/cria-empresa.rb apollo-desk-rails:/tmp/
#   docker exec -e EMPRESA="CD Tech" -e ADMIN_EMAIL="fulano@cdtech-edu.com.br" \
#               -e ADMIN_NOME="Fulano de Tal" \
#               apollo-desk-rails bundle exec rails runner /tmp/cria-empresa.rb
#
# POR QUE ISTO É UM SCRIPT E NÃO "clica no super_admin"
# -----------------------------------------------------
# Onboarding de cliente feito na mão diverge: um esquece o idioma, outro põe o
# papel errado, e a diferença só aparece meses depois. Aqui é reproduzível,
# versionado e confere o efeito no fim.
#
# O MODELO (decidido em 01/set/2026): UMA instância para todos os clientes,
# uma `Account` por empresa, e quem separa uma da outra é o LOGIN — nunca a
# URL. Mesmo desenho do ApolloPlan (workspace) e do ApolloMail (tenant).
#
# ⚠️ A PAREDE É LÓGICA, NÃO FÍSICA. Todas as empresas dividem o mesmo banco e a
# separação é feita pelo aplicativo. Um bug de autorização atravessaria
# empresas — diferente do Apollo Cloud, que usa stack por cliente. É custo
# consciente, e a contrapartida está no contrato: excluir cliente é REMOVER A
# EMPRESA, não destruir o stack.

empresa = ENV['EMPRESA'].presence or abort 'ERRO: defina EMPRESA="Nome do Cliente"'
admin_email = ENV['ADMIN_EMAIL'].presence
admin_nome  = ENV['ADMIN_NOME'].presence

puts "── criando a empresa: #{empresa} ──────────"

conta = Account.find_by(name: empresa)
if conta
  puts "  = empresa já existia (##{conta.id})"
else
  # locale 16 = pt_BR (o mesmo da conta da Apollo). O padrão do Chatwoot é
  # inglês, e cliente brasileiro recebendo o painel em inglês é erro de
  # onboarding que ninguém percebe até o cliente reclamar.
  conta = Account.create!(name: empresa, locale: 16)
  puts "  + empresa criada (##{conta.id})"
end

if admin_email
  usuario = User.find_by(email: admin_email)
  if usuario
    puts "  = pessoa já existe no ApolloDesk (#{usuario.name})"
    puts '    → vai passar a ver DUAS empresas, com o seletor no canto superior esquerdo'
  else
    # Senha aleatória e DESCARTADA de propósito: desde a E2 (02/set) a entrada
    # é pelo ApolloAuth, então a pessoa nunca usa senha aqui. O campo existe
    # porque o Devise exige; ninguém precisa dele.
    #
    # ⚠️ O QUE DE FATO IMPORTA: esta pessoa PRECISA existir no ApolloAuth com
    # ESTE MESMO e-mail. O casamento do SSO é por e-mail (User.from_email), e
    # o JIT está desligado — quem não existe aqui é RECUSADO com
    # "no-account-found" em vez de virar usuário duplicado em silêncio.
    usuario = User.create!(
      name: admin_nome || admin_email.split('@').first,
      email: admin_email,
      password: "Ap#{SecureRandom.hex(20)}!9",
      confirmed_at: Time.current
    )
    puts "  + pessoa criada (#{usuario.name})"
  end
  AccountUser.find_or_create_by!(account: conta, user: usuario) { |au| au.role = :administrator }
  puts '  + vinculada como ADMINISTRADORA da empresa'
end

# ── Administradores gerais da Apollo ───────────────────────────────────────
# Empresa nova nasce com eles. Sem isto, a próxima empresa seria criada sem os
# admins gerais e ninguém notaria até alguém precisar entrar — e aí seria um
# "por que eu não consigo ver a conta do cliente?" sem causa aparente.
caminho_admins = File.expand_path('admins-gerais.rb', __dir__)
if File.exist?(caminho_admins)
  puts
  load caminho_admins
else
  puts
  puts '  ⚠️ admins-gerais.rb não encontrado ao lado — rode-o à parte.'
end

# ── Conferência pelo BANCO, não pelo exit code ──────────────────────────────
puts
puts '── conferindo ─────────────────────────────'
puts format('  %-22s %s', 'empresa', "#{conta.name} (##{conta.id})")
puts format('  %-22s %s', 'idioma', conta.locale)
puts format('  %-22s %s', 'pessoas', AccountUser.where(account: conta).count)
puts format('  %-22s %s', 'caixas de entrada', Inbox.where(account: conta).count)
puts format('  %-22s %s', 'contatos', Contact.where(account: conta).count)

if admin_email
  vistas = User.find_by(email: admin_email).accounts.pluck(:name)
  puts format('  %-22s %s', 'esta pessoa enxerga', vistas.inspect)
end

puts
puts '── o que falta, e não é automático ────────'
puts '  1. A pessoa precisa existir no APOLLOAUTH com este mesmo e-mail.'
puts '     É por e-mail que o SSO casa, e o JIT está desligado: quem não'
puts '     existir aqui é recusado com "no-account-found" — de propósito.'
puts '     Feito isso, ela entra por "Continuar com ApolloAuth". Sem senha.'
puts '  2. Conectar os canais da empresa (WhatsApp, Instagram, e-mail, widget)'
puts '     — cada empresa usa o PRÓPRIO número; nada é compartilhado.'
puts '  3. Contrato e DPA: excluir este cliente = remover esta empresa aqui,'
puts '     não destruir stack. Tem de estar escrito.'
