# ApolloDesk — garante que os administradores gerais da Apollo estejam em
# TODAS as empresas.
#
# Rodar:  docker exec apollo-desk-rails bundle exec rails runner /tmp/admins-gerais.rb
#
# É idempotente e re-executável: rodar de novo não duplica nada. O
# cria-empresa.rb chama a mesma lista, então empresa nova já nasce com eles —
# senão a próxima seria criada sem, e ninguém notaria até precisar entrar.
#
# ⚠️ ISTO DÁ ACESSO A CONVERSA DE CLIENTE, e é uma decisão, não um detalhe.
# Administrador de uma empresa aqui lê TODO o atendimento dela — inclusive as
# conversas com os clientes DELA (o "cliente do cliente"). É coerente com o
# modelo de MSP que a casa já pratica: no ApolloAuth os mesmos dois estão em
# `co-<empresa>-admin` de cada cliente. Mas precisa estar no contrato e no DPA,
# porque é acesso a dado pessoal de terceiro.

ADMINS = {
  'leonardo@apollosolution.com.br' => 'Leonardo Flaminio',
  'guilherme.b@apollosolution.com.br' => 'Guilherme Barbosa'
}.freeze

puts '── administradores gerais em todas as empresas ──'

usuarios = ADMINS.map do |email, nome|
  u = User.find_by(email: email)
  if u.nil?
    # Senha aleatória e descartada: a entrada é pelo ApolloAuth (SSO). Estas
    # duas pessoas já existem no IdP, então o casamento por e-mail funciona.
    u = User.create!(name: nome, email: email,
                     password: "Ap#{SecureRandom.hex(20)}!9", confirmed_at: Time.current)
    puts "  + usuário criado: #{nome}"
  end
  u
end

Account.find_each do |conta|
  usuarios.each do |u|
    vinculo = AccountUser.find_by(account: conta, user: u)
    if vinculo.nil?
      AccountUser.create!(account: conta, user: u, role: :administrator)
      puts format('  + %-24s -> %s', u.name, conta.name)
    elsif vinculo.role != 'administrator'
      # Não silenciar: se alguém rebaixou o admin geral a agente, isso é
      # informação, não algo para corrigir sem avisar.
      vinculo.update!(role: :administrator)
      puts format('  ~ %-24s -> %s (era %s, promovido)', u.name, conta.name, vinculo.role_previously_was)
    end
  end
end

# ── Conferir o EFEITO, não o exit code ─────────────────────────────────────
puts
puts '── conferindo ─────────────────────────────'
falhas = []
Account.find_each do |conta|
  nomes = AccountUser.where(account: conta, role: :administrator)
                     .joins(:user).pluck('users.email')
  faltando = ADMINS.keys - nomes
  falhas << "#{conta.name}: falta #{faltando.join(', ')}" if faltando.any?
  puts format('  %-24s %d administrador(es)', conta.name, nomes.size)
end

if falhas.any?
  puts
  falhas.each { |f| puts "  ERRO: #{f}" }
  exit 1
end
puts
puts "OK: os #{ADMINS.size} administradores gerais estão nas #{Account.count} empresas."
