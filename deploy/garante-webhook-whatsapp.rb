# ApolloDesk — garante que TODA caixa de WhatsApp Cloud recebe mensagem da Meta.
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

puts
puts "OK: #{corrigidos} corrigido(s), #{problemas} problema(s)."
exit 1 if problemas.positive?
