# ApolloDesk — troca a marca do Chatwoot nos lugares que o rebrand de CSS NÃO alcança.
#
# Roda no BUILD da imagem, DEPOIS do rebrand-cores.rb.
#
# POR QUE ESTE SCRIPT EXISTE
# --------------------------
# O rebrand-cores.rb varre `public/vite/assets/*.css`. Isso deixou de fora três
# famílias de arquivo, e o defeito só apareceu quando o Leonardo instalou o PWA
# em 02/set: a janela abria AZUL e escrita "Chatwoot", mesmo com o app inteiro
# verde por dentro.
#
#   1. public/manifest.json  — name/short_name "Chatwoot" e as duas cores do PWA.
#      É daqui que sai o título da janela do app instalado e a cor da tela antes
#      de o app carregar. A aba do navegador já mostrava "ApolloDesk" (vem do
#      <title>), então o sintoma era assimétrico e confundia.
#   2. app/views/layouts/vueapp.html.erb — <meta name="theme-color"> e
#      msapplication-TileColor, que pintam a barra do navegador.
#   3. app/views/**/mailer, base.liquid — os E-MAILS saíam com o azul do
#      Chatwoot. Ninguém tinha reparado porque e-mail transacional a gente lê
#      sem olhar. Não foi pedido, mas é o mesmo defeito.
#
# ⚠️ POR QUE AQUI NÃO SE VARRE POR MATIZ, ao contrário do rebrand-cores.rb.
# Nos assets há dezenas de cores em SVG embutido com o hex URL-encoded
# (`%23rrggbb`): bandeiras de país do seletor de telefone, verde do WhatsApp,
# logos de parceiro. Várias caem dentro da faixa de "azul" — `%233E63DD` tem
# matiz 226 e passaria no teste. Repintar bandeira de verde seria um defeito
# pior que o que estamos consertando, e não dá para verificar uma a uma.
# Então aqui a troca é NOMINAL: só os azuis que comprovadamente são do
# Chatwoot.

AZUIS_DO_CHATWOOT = %w[2781f6 1f93ff].freeze

# O primário do app depois do rebrand (--blue-9 no tema claro), conferido no CSS
# construído. Usar outro verde faria o PWA destoar do próprio app.
VERDE = '#058546'.freeze
NOME = 'ApolloDesk'.freeze

def troca_azuis(texto)
  n = 0
  AZUIS_DO_CHATWOOT.each do |azul|
    # Pega #2781F6, %232781f6 e 2781F6 solto, em qualquer caixa.
    texto = texto.gsub(/(#|%23)?#{azul}/i) do |achado|
      n += 1
      achado.start_with?('%23') ? "%23#{VERDE.delete('#')}" : VERDE
    end
  end
  [texto, n]
end

def edita(caminho, descricao)
  unless File.exist?(caminho)
    puts "  ! #{descricao}: arquivo não existe (#{caminho})"
    return 0
  end
  original = File.read(caminho)
  novo, n = yield(original)
  if novo == original
    puts format('  = %-46s sem alteração', descricao)
    return 0
  end
  File.write(caminho, novo)
  puts format('  + %-46s %d troca(s)', descricao, n)
  n
end

puts '── rebrand fora do CSS ────────────────────'

total = 0

# 1) O manifest do PWA ──────────────────────────────────────────────────────
# Aqui NÃO se usa regex: o manifest é JSON, e mexer em JSON com gsub é como
# consertar o texto sem entender a estrutura — funciona até o dia em que o
# upstream reordena um campo. Parseia, altera, reserializa.
total += edita('public/manifest.json', 'manifest.json: nome, cores e ícone 512') do |s|
  require 'json'
  m = JSON.parse(s)
  n = 0

  %w[name short_name].each do |campo|
    next if m[campo] == NOME

    m[campo] = NOME
    n += 1
  end

  %w[theme_color background_color].each do |campo|
    next if m[campo].to_s.casecmp(VERDE).zero?

    m[campo] = VERDE
    n += 1
  end

  # ⚠️ O manifest do Chatwoot para em 192x192. O Chrome documenta 192 E 512
  # como requisito de instalação, e sem o 512 ele ainda usa o 192 esticado no
  # atalho — fica borrado. O arquivo já existe em public/, só nunca foi
  # declarado.
  if File.exist?('public/favicon-512x512.png') &&
     m['icons'].none? { |i| i['sizes'] == '512x512' }
    m['icons'] << { 'src' => '/favicon-512x512.png', 'sizes' => '512x512',
                    'type' => 'image/png', 'density' => '4.0' }
    n += 1
  end

  [JSON.pretty_generate(m) + "\n", n]
end

# 2) As meta tags do layout ─────────────────────────────────────────────────
total += edita('app/views/layouts/vueapp.html.erb', 'vueapp.html.erb: theme-color e TileColor') do |s|
  troca_azuis(s)
end

# 3) Os e-mails ─────────────────────────────────────────────────────────────
Dir['app/views/layouts/mailer/*', 'app/views/devise/mailer/*'].select { |f| File.file?(f) }.sort.each do |arq|
  total += edita(arq, "e-mail: #{File.basename(arq)}") { |s| troca_azuis(s) }
end

# 4) O painel de superadmin ─────────────────────────────────────────────────
total += edita('app/views/super_admin/application/_icons.html.erb', 'super_admin: _icons.html.erb') do |s|
  troca_azuis(s)
end

# 5) O azul URL-encoded que sobrou nos assets ───────────────────────────────
# Um ícone SVG embutido em data-URI usa `fill='%232781f6'`. O rebrand-cores.rb
# procurava `#2781f6` e passou direto — e o guarda dele, que também só olhava
# `#`, deu OK. É a troca NOMINAL de que fala o cabeçalho: aqui não se varre por
# matiz, para não repintar bandeira de país.
Dir['public/vite/assets/*.css'].sort.each do |arq|
  n = edita(arq, "assets: #{File.basename(arq)}") do |s|
    achados = AZUIS_DO_CHATWOOT.sum { |a| s.scan(/%23#{a}/i).size }
    next [s, 0] if achados.zero?

    troca_azuis(s)
  end
  total += n
end

# ── Conferir o EFEITO, não o exit code ─────────────────────────────────────
# O guarda do rebrand-cores.rb contava só #rrggbb, #rrggbbaa e tokens — foi
# exatamente por isso que o `%232781f6` passou batido e o PWA saiu azul. Aqui o
# guarda procura as MESMAS formas que o script troca, senão ele aprova o que
# não inspeciona.
puts
puts '── conferindo ─────────────────────────────'

alvos = ['public/manifest.json', 'app/views/layouts/vueapp.html.erb'] +
        Dir['app/views/layouts/mailer/*', 'app/views/devise/mailer/*'].select { |f| File.file?(f) }

restos = alvos.filter_map do |arq|
  conteudo = File.read(arq)
  achados = AZUIS_DO_CHATWOOT.sum { |a| conteudo.scan(/#{a}/i).size }
  achados.positive? ? "#{arq}: #{achados} azul(is)" : nil
end

nome_resto = File.read('public/manifest.json').scan(/"(?:short_name|name)"\s*:\s*"Chatwoot"/).size

puts format('  %-46s %s', 'azul do Chatwoot nos arquivos alvo', restos.empty? ? 'nenhum' : restos.join(' · '))
puts format('  %-46s %s', 'nome "Chatwoot" no manifest', nome_resto.zero? ? 'nenhum' : "#{nome_resto} restante(s)")

# O `%23` nos assets é o defeito que originou este script: ele escapou tanto da
# troca quanto do guarda do rebrand-cores.rb.
assets_resto = Dir['public/vite/assets/*.css'].sum do |arq|
  AZUIS_DO_CHATWOOT.sum { |a| File.read(arq).scan(/%23#{a}/i).size }
end
puts format('  %-46s %s', 'azul URL-encoded (%23) nos assets', assets_resto.zero? ? 'nenhum' : "#{assets_resto} restante(s)")

puts
if restos.any? || nome_resto.positive? || assets_resto.positive?
  puts 'ERRO: sobrou marca do Chatwoot fora do CSS.'
  exit 1
end
puts "OK: #{total} troca(s) aplicada(s); nada do Chatwoot restou fora do CSS."
