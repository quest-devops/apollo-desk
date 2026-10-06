# ApolloDesk — garante que TODA caixa de WhatsApp Cloud e de Messenger recebe mensagem da Meta.
#
# Rodar (cron, a cada 10 min — ver /root/garante-webhook-whatsapp.sh no apollo-prod):
#   docker exec apollo-desk-rails bundle exec rails runner /tmp/garante-webhook-whatsapp.rb
#
#   ENSAIO=1   só mostra o que faria
#
# POR QUE ISTO EXISTE (25/set/2026)
# --------------------------------
# O Cadastro incorporado do Chatwoot 4.17.1 cria a caixa e PARA: não assina a
# WABA nova ao nosso app (`POST /{waba}/subscribed_apps`) nem grava o webhook
# próprio do número (`POST /{phone_number_id}/register`-callback). Resultado: a
# Meta entrega a mensagem no callback de NÍVEL DE APP — que aponta para o
# endereço do número da Apollo — e o Desk descarta por não bater o telefone da
# URL. Sintoma: "mandei mensagem e não caiu no Desk", sem erro em lugar nenhum.
# Foi assim com a primeira caixa da Dagostino (canal 3, +15554727257).
#
# O caminho manual (formulário) faz os dois passos sozinho, mas estoura o
# rack-timeout de 15 s e deixa o canal sem webhook (ver README). Então o guarda
# vale para os dois caminhos: lê o estado NA META, nunca no Chatwoot, e só age
# no que falta. Idempotente; rodar de novo não faz nada.

require 'httparty'

ENSAIO = ENV['ENSAIO'].present?
API = 'https://graph.facebook.com/v22.0'.freeze

def mask(texto, token)
  texto.to_s.gsub(token, '***')
end

puts "── guarda de webhook do WhatsApp ── #{Time.current.strftime('%d/%m %H:%M')}#{ENSAIO ? '  [ENSAIO]' : ''}"

problemas = 0
corrigidos = 0

Channel::Whatsapp.where(provider: 'whatsapp_cloud').includes(:inbox).find_each do |ch|
  pc = ch.provider_config || {}
  tok = pc['api_key'].to_s
  pid = pc['phone_number_id'].to_s
  waba = pc['business_account_id'].to_s
  rotulo = "canal ##{ch.id} #{ch.phone_number} (#{ch.inbox&.name})"

  if tok.empty? || pid.empty? || waba.empty?
    puts "  ! #{rotulo}: provider_config incompleto (token/phone_number_id/waba) — pulando"
    problemas += 1
    next
  end

  esperado = Whatsapp::WebhookSetupService.new(ch).send(:build_callback_url)

  # 1) A WABA está assinada ao NOSSO app?
  apps = HTTParty.get("#{API}/#{waba}/subscribed_apps?access_token=#{tok}")
  nosso = GlobalConfig.get('WHATSAPP_APP_ID')['WHATSAPP_APP_ID'].to_s
  assinada = apps.parsed_response.to_h.fetch('data', []).any? { |a| a['whatsapp_business_api_data'].to_h['id'].to_s == nosso }

  # 2) O número tem webhook PRÓPRIO apontando para o endereço dele no Desk?
  cfg = HTTParty.get("#{API}/#{pid}?fields=webhook_configuration&access_token=#{tok}")
  atual = cfg.parsed_response.to_h.dig('webhook_configuration', 'phone_number').to_s
  webhook_ok = atual == esperado

  if cfg.parsed_response.to_h['error']
    puts "  ! #{rotulo}: Meta recusou a leitura — #{mask(cfg.parsed_response.to_h['error']['message'], tok)} (token vencido? ver vigia-token)"
    problemas += 1
    next
  end

  if assinada && webhook_ok
    puts "  = #{rotulo}: ok"
    next
  end

  puts "  #{ENSAIO ? '~' : '+'} #{rotulo}: #{assinada ? '' : 'WABA não assinada; '}#{webhook_ok ? '' : "webhook '#{atual.presence || '(nenhum)'}' ≠ esperado"}"
  next if ENSAIO

  unless assinada
    r = HTTParty.post("#{API}/#{waba}/subscribed_apps?access_token=#{tok}")
    puts "     ↳ subscribed_apps: #{mask(r.body, tok)}"
  end
  unless webhook_ok
    begin
      Whatsapp::WebhookSetupService.new(ch).register_callback
      puts '     ↳ register_callback: ok'
    rescue StandardError => e
      puts "     ↳ register_callback: ERRO #{mask(e.message, tok)}"
    end
  end

  # ── Conferir o EFEITO pela Meta ──────────────────────────────────────────
  depois = HTTParty.get("#{API}/#{pid}?fields=webhook_configuration&access_token=#{tok}")
  agora = depois.parsed_response.to_h.dig('webhook_configuration', 'phone_number').to_s
  apps2 = HTTParty.get("#{API}/#{waba}/subscribed_apps?access_token=#{tok}")
  assinada2 = apps2.parsed_response.to_h.fetch('data', []).any? { |a| a['whatsapp_business_api_data'].to_h['id'].to_s == nosso }
  if agora == esperado && assinada2
    puts '     ↳ conferido na Meta: ok'
    corrigidos += 1
  else
    puts "     ↳ AINDA ERRADO: webhook='#{agora}' assinada=#{assinada2}"
    problemas += 1
  end
end

puts "WhatsApp: #{corrigidos} corrigido(s), #{problemas} problema(s)."

# ── Messenger (06/out/2026) ───────────────────────────────────────────────
# Mesma classe de falha silenciosa: o webhook do objeto `page` estava em /bot,
# verificado e ativo, mas SEM CAMPOS assinados no nível do app — a Página fica
# ligada ao app (subscribed_apps ok) e nenhuma mensagem chega. Aqui conferimos
# (1) os campos do webhook do app e (2) cada Página ligada ao app, e só agimos
# no que falta. Mesmo ENSAIO, mesma saída.
CAMPOS_PAGE = %w[messages messaging_postbacks message_deliveries message_reads message_echoes standby messaging_handovers].freeze
# Por Página, o próprio Chatwoot assina este conjunto (sem postbacks) — conferimos o mesmo, para não brigar com ele.
CAMPOS_PAGINA = (CAMPOS_PAGE - %w[messaging_postbacks]).freeze
fb_id  = GlobalConfigService.load('FB_APP_ID', nil).to_s
fb_sec = GlobalConfigService.load('FB_APP_SECRET', nil).to_s
fb_vt  = GlobalConfigService.load('FB_VERIFY_TOKEN', nil).to_s
app_tok = "#{fb_id}|#{fb_sec}"
callback_bot = "#{ENV.fetch('FRONTEND_URL', 'https://app.apollodesk.com.br')}/bot"

puts
puts '── guarda de webhook do Messenger ──'
if fb_id.empty? || fb_sec.empty?
  puts '  ! FB_APP_ID/FB_APP_SECRET ausentes — pulando'
  problemas += 1
else
  subs = HTTParty.get("#{API}/#{fb_id}/subscriptions?access_token=#{app_tok}").parsed_response.to_h
  pg = subs.fetch('data', []).find { |s| s['object'] == 'page' } || {}
  campos = (pg['fields'] || []).map { |f| f['name'] }
  faltam = CAMPOS_PAGE - campos
  if pg['callback_url'] == callback_bot && pg['active'] && faltam.empty?
    puts "  = app #{fb_id}: webhook page ok (#{campos.size} campos)"
  else
    puts "  #{ENSAIO ? '~' : '+'} app #{fb_id}: webhook page callback='#{pg['callback_url']}' ativo=#{pg['active']} faltam=#{faltam.join(',').presence || '(nenhum)'}"
    unless ENSAIO
      r = HTTParty.post("#{API}/#{fb_id}/subscriptions", body: { object: 'page', callback_url: callback_bot, verify_token: fb_vt,
                                                                  fields: CAMPOS_PAGE.join(','), access_token: app_tok })
      puts "     ↳ subscriptions: #{mask(mask(r.body, fb_sec), fb_vt)}"
      pg2 = HTTParty.get("#{API}/#{fb_id}/subscriptions?access_token=#{app_tok}").parsed_response.to_h.fetch('data', []).find { |s| s['object'] == 'page' } || {}
      ok = (CAMPOS_PAGE - (pg2['fields'] || []).map { |f| f['name'] }).empty? && pg2['callback_url'] == callback_bot
      puts ok ? '     ↳ conferido na Meta: ok' : "     ↳ AINDA ERRADO: #{pg2}"
      ok ? corrigidos += 1 : problemas += 1
    end
  end

  Channel::FacebookPage.includes(:inbox).find_each do |ch|
    rotulo = "página #{ch.page_id} (#{ch.inbox&.name})"
    tok = ch.page_access_token.to_s
    r = HTTParty.get("#{API}/#{ch.page_id}/subscribed_apps?access_token=#{tok}").parsed_response.to_h
    if r['error']
      puts "  ! #{rotulo}: Meta recusou a leitura — #{mask(r['error']['message'], tok)} (reconectar a Página no Desk)"
      problemas += 1
      next
    end
    app = r.fetch('data', []).find { |a| a['id'].to_s == fb_id }
    faltam_pg = CAMPOS_PAGINA - (app ? app['subscribed_fields'].to_a : [])
    if app && faltam_pg.empty?
      puts "  = #{rotulo}: ok"
      next
    end
    puts "  #{ENSAIO ? '~' : '+'} #{rotulo}: #{app ? "faltam #{faltam_pg.join(',')}" : 'Página não ligada ao app'}"
    next if ENSAIO

    r2 = HTTParty.post("#{API}/#{ch.page_id}/subscribed_apps", body: { subscribed_fields: CAMPOS_PAGINA.join(','), access_token: tok })
    puts "     ↳ subscribed_apps: #{mask(r2.body, tok)}"
    r3 = HTTParty.get("#{API}/#{ch.page_id}/subscribed_apps?access_token=#{tok}").parsed_response.to_h
    app3 = r3.fetch('data', []).find { |a| a['id'].to_s == fb_id }
    ok = app3 && (CAMPOS_PAGINA - app3['subscribed_fields'].to_a).empty?
    puts ok ? '     ↳ conferido na Meta: ok' : "     ↳ AINDA ERRADO: #{mask(r3.to_s, tok)}"
    ok ? corrigidos += 1 : problemas += 1
  end
end

puts
puts "TOTAL: #{corrigidos} corrigido(s), #{problemas} problema(s)."
exit 1 if problemas.positive?
