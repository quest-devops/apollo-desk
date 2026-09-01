# ApolloDesk — escreve a identidade da instalação na tabela installation_configs.
#
# Rodar:  docker exec apollo-desk-rails bundle exec rails runner /app/deploy/set-marca.rb
#
# POR QUE UM SCRIPT, E NÃO O .env
# --------------------------------
# Verificado em 28/ago/2026: NÃO existe variável de ambiente de marca no
# Chatwoot. INSTALLATION_NAME, BRAND_NAME e companhia são valores HARDCODED em
# config/installation_config.yml, carregados para o banco no primeiro seed.
# Pôr essas chaves no .env não faz nada — foi testado, o .env dizia ApolloDesk
# e o banco continuou "Chatwoot".
#
# E no YAML elas são `locked: true`, então também não aparecem na tela de
# Installation Config do super_admin. Escrever na tabela é o único caminho.
#
# O que garante que isto PERSISTE é o DISABLE_ENTERPRISE=true do .env: sem ele,
# o job Internal::ReconcilePlanConfigService reverte tudo para "Chatwoot" em
# background — o rebrand parece ter funcionado e some depois.

MARCA = {
  'INSTALLATION_NAME' => 'ApolloDesk',
  'BRAND_NAME'        => 'ApolloDesk',
  'BRAND_URL'         => 'https://apollosolution.com.br',
  'WIDGET_BRAND_URL'  => 'https://apollosolution.com.br',
  # ⚠️ Caminhos VERSIONADOS de propósito. Os nomes originais são servidos com
  # cache de um ano; enquanto a marca apontava para eles, o navegador de quem
  # já tinha aberto o app seguia mostrando o balão azul do Chatwoot mesmo com
  # o arquivo certo no servidor. URL nova é a única forma de furar isso sem
  # depender de o usuário limpar o cache. Ao trocar a marca, subir o sufixo.
  'LOGO'              => '/brand-assets/apollodesk-logo-v4.svg',
  'LOGO_DARK'         => '/brand-assets/apollodesk-logo-dark-v4.svg',
  'LOGO_THUMBNAIL'    => '/brand-assets/apollodesk-icone-v4.svg',
  'TERMS_URL'         => 'https://apollosolution.com.br/termos',
  'PRIVACY_URL'       => 'https://apollosolution.com.br/privacidade'
}.freeze

puts '── escrevendo ─────────────────────────────'
MARCA.each do |nome, valor|
  cfg = InstallationConfig.find_by(name: nome)
  if cfg.nil?
    InstallationConfig.create!(name: nome, value: valor, locked: true)
    puts "  + #{nome} (criado)"
  else
    cfg.update!(value: valor)
    puts "  ~ #{nome}"
  end
end

# O Chatwoot serve estes valores de um cache; sem limpar, a interface continua
# mostrando o nome antigo e a conclusão errada é "não funcionou".
GlobalConfig.clear_cache

puts
puts '── conferindo pelo BANCO (nao pelo exit code) ──'
erros = 0
MARCA.each do |nome, esperado|
  lido = InstallationConfig.find_by(name: nome)&.value
  ok = lido.to_s == esperado
  erros += 1 unless ok
  puts format('  %-18s %s %s', nome, ok ? 'OK ' : 'ERRO', lido.inspect)
end

puts
if erros.zero?
  puts "OK: #{MARCA.size} chaves gravadas e conferidas."
  puts 'Falta o teste que importa: REINICIAR e conferir de novo (e o que pega o'
  puts 'ReconcilePlanConfigService). Conferir agora nao prova persistencia.'
else
  puts "ERRO: #{erros} chave(s) nao gravaram."
  exit 1
end
