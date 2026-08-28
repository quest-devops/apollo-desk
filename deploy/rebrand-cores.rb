# ApolloTeam — troca a paleta AZUL do Chatwoot pelo VERDE da Apollo.
#
# Roda no BUILD da imagem derivada (ver Dockerfile), nunca no container em
# execução: mudança feita no container some no primeiro `pull` e não fica em
# lugar nenhum do git.
#
# POR QUE NÃO É UM `sed`
# ----------------------
# A primeira versão era. Ela trocava uma lista fixa de 6 valores e falhou em
# duas frentes:
#
#   1. A paleta do Chatwoot tem MUITO mais que 6 azuis (#086de0, #1073e9,
#      #1284e7, #9bc3fc, #daecff, #d6e1ff...). Sobrava azul em texto e ícone.
#   2. `sed` não sabe em QUE REGRA está. E o tema escuro precisa de um verde
#      diferente do tema claro: no claro o verde tem de ser escuro para o texto
#      branco ser legível; no escuro, o verde tem de ser o CLARO da marca
#      (#2FE68C), senão some no fundo preto.
#
# Este script varre regra a regra, identifica azul por MATIZ (não por lista
# fixa) e escolhe o verde conforme a regra seja de tema claro ou escuro.
#
# ⚠️ ATRELADO À TAG DA IMAGEM — o compose fixa chatwoot/chatwoot:v4.17.1.

ASSETS = '/app/public/vite/assets'.freeze

# Matiz do verde Apollo: #2FE68C e #0A7D47 estão ambos em ~151°.
MATIZ_VERDE = 151.0
# Saturação/luminosidade alvo do verde claro da marca (#2FE68C).
SAT_MARCA = 0.785
LUM_MARCA = 0.543

def rgb_para_hsl(r, g, b)
  r /= 255.0; g /= 255.0; b /= 255.0
  max = [r, g, b].max; min = [r, g, b].min
  l = (max + min) / 2
  return [0.0, 0.0, l] if (max - min).abs < 1e-9

  d = max - min
  s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  h = case max
      when r then ((g - b) / d) % 6
      when g then (b - r) / d + 2
      else        (r - g) / d + 4
      end
  [h * 60, s, l]
end

def hsl_para_rgb(h, s, l)
  h = h % 360
  c = (1 - (2 * l - 1).abs) * s
  x = c * (1 - ((h / 60.0) % 2 - 1).abs)
  m = l - c / 2
  r, g, b = case (h / 60).floor
            when 0 then [c, x, 0] when 1 then [x, c, 0] when 2 then [0, c, x]
            when 3 then [0, x, c] when 4 then [x, 0, c] else [c, 0, x]
            end
  [(r + m), (g + m), (b + m)].map { |v| (v * 255).round.clamp(0, 255) }
end

# Azul do Chatwoot = matiz 195°–230° com saturação real.
#
# O intervalo é fechado de propósito. Acima de 230° começam as marcas de
# TERCEIRO que aparecem dentro do produto (Linear #5e6ad2 em 234°, Instagram
# #833ab4, #6958ad) — repintar essas de verde seria erro, não rebrand. O teto
# foi baixado de 235° para 230° justamente porque o Linear passou na primeira
# rodada; os azuis do Chatwoot ficam todos em ~210°, bem longe da borda. E o corte de
# saturação em 0.30 protege os CINZAS AZULADOS da interface (#374151, #73879c),
# que são texto e borda neutros: pintá-los de verde deixaria a tela doente.
#
# ⚠️ A saturação HSL sozinha NÃO basta, e isso quase estragou a tela: o
# cinza-quase-preto #111827 (Tailwind gray-900, fundo do tema escuro) tem
# matiz 221° e saturação 0.39 — passaria no teste e viraria verde, tingindo o
# fundo inteiro. O que o separa de um azul de verdade é a CROMA ABSOLUTA:
# #111827 tem 0.086, enquanto o azul principal tem 0.81. Daí o terceiro corte.
def azul?(r, g, b)
  h, s, = rgb_para_hsl(r, g, b)
  croma = ([r, g, b].max - [r, g, b].min) / 255.0
  h >= 195 && h <= 230 && s >= 0.30 && croma >= 0.12
end

# O verde depende do TEMA da regra:
#
# - tema claro  → verde escuro (família #0A7D47). O emerald da marca é lindo
#                 como símbolo e ilegível como fundo de botão com texto branco.
# - tema escuro → verde CLARO da marca (#2FE68C). Foi o pedido do Leonardo, e
#                 é também o certo: verde escuro sobre fundo preto desaparece.
#
# Tons muito claros (L > 0.80) são FUNDO, não texto — nesses a luminosidade é
# preservada nos dois temas, senão um fundo suave viraria um bloco verde chapado.
def verde(r, g, b, escuro:)
  h, s, l = rgb_para_hsl(r, g, b)

  if escuro
    # ⚠️ No tema escuro a LUMINOSIDADE É PRESERVADA, e isso não é detalhe.
    # A escala do tema escuro é invertida: --blue-3 é um fundo quase preto e
    # --blue-11 é texto claro. Forçar todos ao verde da marca (como a primeira
    # versão fazia) pintaria o FUNDO de verde-limão. Preservando a luminosidade
    # e trocando só matiz e saturação, cada tom continua no seu papel — e o
    # tom principal (#2781F6, L=0.56) cai exatamente em #2FE68C, que é o verde
    # claro da Apollo que o Leonardo pediu.
    return hsl_para_rgb(MATIZ_VERDE, SAT_MARCA, l)
  end

  # Tema claro: tons muito claros são FUNDO — preservar a luminosidade, senão
  # um fundo suave vira bloco verde chapado.
  return hsl_para_rgb(MATIZ_VERDE, [s, 0.75].min, l) if l > 0.80
  # Tons médios escurecem pouco; os fortes escurecem até o verde da casa
  # (#0A7D47), para texto branco por cima continuar legível.
  return hsl_para_rgb(MATIZ_VERDE, [s, 0.70].max, l * 0.80) if l > 0.62

  hsl_para_rgb(MATIZ_VERDE, [s, 0.85].max, l * 0.48)
end

def hex(rgb) = format('#%02x%02x%02x', *rgb)

trocas = Hash.new(0)
total = 0

def converte(texto, escuro:, trocas:)
  n = 0

  # ⚠️ TOKENS DE COR — o caso que fez a primeira rodada parecer que "nada
  # mudou". A paleta do Chatwoot não vive só nos valores literais: ela é
  # declarada como custom property com os canais SOLTOS, sem `rgb(` na frente:
  #
  #     --blue-9: 39 129 246;        --border-blue: 39, 129, 246, .5;
  #
  # e as regras a consomem com `rgb(var(--blue-9) / …)`. Como o literal de
  # fallback ao lado ERA convertido, o CSS ficava com a cor certa na primeira
  # declaração e a errada na segunda — e a segunda vence. Resultado na tela:
  # verde no botão e azul no texto, exatamente o que o Leonardo viu.
  texto = texto.gsub(/(--[a-z0-9-]+\s*:\s*)(\d{1,3})([,\s]\s*)(\d{1,3})([,\s]\s*)(\d{1,3})/i) do
    pre, r, sep1, g, sep2, b = Regexp.last_match.captures
    ri, gi, bi = r.to_i, g.to_i, b.to_i
    if azul?(ri, gi, bi)
      nr, ng, nb = verde(ri, gi, bi, escuro: escuro)
      trocas["token #{r} #{g} #{b} -> #{nr} #{ng} #{nb}#{escuro ? ' (escuro)' : ''}"] += 1
      n += 1
      "#{pre}#{nr}#{sep1}#{ng}#{sep2}#{nb}"
    else
      "#{pre}#{r}#{sep1}#{g}#{sep2}#{b}"
    end
  end

  # #rrggbbaa — hex com alfa. O padrão de 6 dígitos NÃO pega estes (não há
  # fronteira de palavra entre o 6º e o 7º dígito), e é assim que o Chatwoot
  # escreve os estados de hover e os fundos translúcidos: #2781f61a, #2781f680.
  texto = texto.gsub(/#([0-9a-fA-F]{6})([0-9a-fA-F]{2})\b/) do |m|
    c = Regexp.last_match(1)
    alfa = Regexp.last_match(2)
    r, g, b = [c[0, 2], c[2, 2], c[4, 2]].map { |x| x.to_i(16) }
    if azul?(r, g, b)
      novo = format('#%02x%02x%02x%s', *verde(r, g, b, escuro: escuro), alfa)
      trocas["#{m.downcase} -> #{novo}#{escuro ? ' (escuro)' : ''}"] += 1
      n += 1
      novo
    else
      m
    end
  end

  # #rrggbb
  texto = texto.gsub(/#([0-9a-fA-F]{6})\b/) do |m|
    c = Regexp.last_match(1)
    r, g, b = [c[0, 2], c[2, 2], c[4, 2]].map { |x| x.to_i(16) }
    if azul?(r, g, b)
      novo = format('#%02x%02x%02x', *verde(r, g, b, escuro: escuro))
      trocas["#{m.downcase} -> #{novo}#{escuro ? ' (escuro)' : ''}"] += 1
      n += 1
      novo
    else
      m
    end
  end
  # rgb(r g b) — forma que o Tailwind usa com opacidade
  texto = texto.gsub(/rgb\((\d{1,3}) (\d{1,3}) (\d{1,3})/) do |m|
    r, g, b = Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i
    if azul?(r, g, b)
      nr, ng, nb = verde(r, g, b, escuro: escuro)
      trocas["rgb(#{r} #{g} #{b}) -> rgb(#{nr} #{ng} #{nb})#{escuro ? ' (escuro)' : ''}"] += 1
      n += 1
      "rgb(#{nr} #{ng} #{nb}"
    else
      m
    end
  end
  [texto, n]
end

Dir["#{ASSETS}/*.css"].sort.each do |arq|
  css = File.read(arq)
  n_arq = 0
  # Varre REGRA A REGRA. O `[^{}]+` não atravessa chave, então este mesmo
  # padrão pega tanto regra solta quanto regra dentro de @media — nos dois
  # casos o seletor capturado é só o da regra, sem o cabeçalho do @media.
  novo = css.gsub(/([^{}]+)\{([^{}]*)\}/) do
    seletor = Regexp.last_match(1)
    decls   = Regexp.last_match(2)
    escuro  = seletor.include?('.dark')
    conv, n = converte(decls, escuro: escuro, trocas: trocas)
    n_arq += n
    "#{seletor}{#{conv}}"
  end
  # Segunda passada, no arquivo inteiro. A varredura por regra cobre o caso
  # normal e é o que permite distinguir tema escuro — mas não alcança cor que
  # esteja fora de um corpo de regra (at-rule aninhada em dois níveis, por
  # exemplo). Sem esta passada sobraram 78 azuis, e o guarda do fim reprovava
  # o build com razão. Aqui o tema não é inferível, então vale o claro.
  novo, n_resto = converte(novo, escuro: false, trocas: trocas)
  n_arq += n_resto
  next if n_arq.zero?

  File.write(arq, novo)
  puts format('  %-34s %4d cores', File.basename(arq), n_arq)
  total += n_arq
end

# Nos .js não há seletor para inspecionar; são cores de ícone e de estado,
# tratadas como tema claro.
Dir["#{ASSETS}/*.js"].sort.each do |arq|
  js = File.read(arq)
  novo, n = converte(js, escuro: false, trocas: trocas)
  next if n.zero?

  File.write(arq, novo)
  puts format('  %-34s %4d cores', File.basename(arq), n)
  total += n
end

puts
puts "TOTAL de cores trocadas: #{total}"
puts
puts 'Mapa aplicado (as 18 mais frequentes):'
trocas.sort_by { |_, v| -v }.first(18).each { |k, v| puts format('  %-46s x%d', k, v) }

# Conferir o EFEITO, não o exit code — regra da casa.
abort "ERRO: so #{total} trocas. A paleta do Chatwoot provavelmente mudou nesta versao." if total < 300

# ⚠️ O guarda tem de olhar as TRÊS formas. A versão anterior só contava hex de
# 6 dígitos e por isso deu "OK" com a paleta de TOKENS inteira ainda azul — um
# guarda que aprova o que não inspeciona é pior que nenhum, porque encerra a
# investigação.
def conta_azuis(txt)
  n = txt.scan(/#([0-9a-fA-F]{6})(?![0-9a-fA-F])/).count do |(c)|
    r, g, b = [c[0, 2], c[2, 2], c[4, 2]].map { |x| x.to_i(16) }
    azul?(r, g, b)
  end
  n += txt.scan(/#([0-9a-fA-F]{6})[0-9a-fA-F]{2}\b/).count do |(c)|
    r, g, b = [c[0, 2], c[2, 2], c[4, 2]].map { |x| x.to_i(16) }
    azul?(r, g, b)
  end
  n + txt.scan(/--[a-z0-9-]+\s*:\s*(\d{1,3})[,\s]\s*(\d{1,3})[,\s]\s*(\d{1,3})/i)
         .count { |(r, g, b)| azul?(r.to_i, g.to_i, b.to_i) }
end

resto = Dir["#{ASSETS}/*.css", "#{ASSETS}/*.js"].sum { |arq| conta_azuis(File.read(arq)) }
abort "ERRO: ainda restam #{resto} azuis em css/js." if resto.positive?
puts
puts 'OK: nenhum azul de interface restante em css/js.'
