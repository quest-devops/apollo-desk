# ApolloDesk — faz o Embedded Signup do Chatwoot chamar a Meta na versão atual (v4).
#
# Roda no BUILD da imagem, depois do rebrand.
#
# O DEFEITO (15/set/2026)
# -----------------------
# Com o app aprovado e a Apollo já Tech Provider, o botão "Conectar com o
# Facebook" do Desk devolvia "Parece que esse app não está disponível — precisa
# de pelo menos uma supported permission". A MESMA configuração de login
# (2208070036432193), aberta pela página de teste da própria Meta, funcionava.
# A diferença estava nos parâmetros do FB.login que o Chatwoot 4.17.1 manda:
#
#   extras: { setup: {}, featureType: 'whatsapp_business_app_onboarding',
#             sessionInfoVersion: '3' }
#
#   - NÃO informa `version` → a Meta cai na v2 do Cadastro incorporado, que
#     ela aposenta em 15/out/2026;
#   - pede `featureType` de COEXISTÊNCIA (cliente que mantém o app WhatsApp
#     Business no celular), recurso que exige webhooks extras (history,
#     smb_app_state_sync) que o Chatwoot não assina.
#
# A página de teste da Meta que funcionou usava: versão v4, sessionInfoVersion
# 3, "Tipo de recurso: Nenhum". É exatamente isso que este patch faz o Desk
# mandar. Coexistência fica para depois, como decisão separada — e quando for,
# entra aqui com os webhooks correspondentes.
#
# POR QUE NO BUNDLE E NÃO NA FONTE
# --------------------------------
# A imagem oficial já vem com o Vite compilado; recompilar o frontend a cada
# release é a dívida que decidimos não pegar. A fonte (utils.js) é editada
# junto só para quem ler o container não achar um bundle que contradiz o
# código. A âncora é a string exata do bundle; se a versão do Chatwoot mudar e
# ela sumir, o build FALHA — melhor do que entregar um botão que não abre.

ANTES_BUNDLE = 'featureType:"whatsapp_business_app_onboarding",sessionInfoVersion:"3"'.freeze
DEPOIS_BUNDLE = 'sessionInfoVersion:"3",version:"v4"'.freeze

ANTES_FONTE = "          featureType: 'whatsapp_business_app_onboarding',\n          sessionInfoVersion: '3',".freeze
DEPOIS_FONTE = "          sessionInfoVersion: '3',\n          version: 'v4',".freeze

puts '── patch do Embedded Signup (v4, sem coexistência) ──'

tocados = 0
Dir['public/vite/assets/*.js'].sort.each do |arq|
  s = File.read(arq)
  next unless s.include?(ANTES_BUNDLE)

  File.write(arq, s.gsub(ANTES_BUNDLE, DEPOIS_BUNDLE))
  tocados += 1
  puts "  + #{File.basename(arq)}"
end
abort 'ERRO: âncora do FB.login não encontrada em nenhum bundle — a versão do Chatwoot mudou; revisar o patch.' if tocados.zero?

fonte = 'app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js'
if File.exist?(fonte) && File.read(fonte).include?(ANTES_FONTE)
  File.write(fonte, File.read(fonte).sub(ANTES_FONTE, DEPOIS_FONTE))
  puts '  + utils.js (fonte, por coerência)'
end

# ── Conferir o EFEITO ──────────────────────────────────────────────────────
resto = Dir['public/vite/assets/*.js'].count { |a| File.read(a).include?('whatsapp_business_app_onboarding') }
com_v4 = Dir['public/vite/assets/*.js'].count { |a| File.read(a).include?(DEPOIS_BUNDLE) }
puts
puts format('  bundles com version:"v4"            %d', com_v4)
puts format('  bundles ainda pedindo coexistência  %d', resto)
abort 'ERRO: patch incompleto.' if com_v4.zero? || resto.positive?
puts "OK: Embedded Signup em v4 em #{tocados} bundle(s)."
