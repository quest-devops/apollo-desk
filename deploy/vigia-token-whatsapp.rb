# ApolloDesk — avisa ANTES de o token do WhatsApp expirar.
#
# Rodar:
#   docker exec apollo-desk-rails bundle exec rails runner /tmp/vigia-token-whatsapp.rb
#
# Cron diário (ver deploy/README ou o crontab do apollo-prod).
#
# POR QUE ISTO EXISTE
# -------------------
# O modelo de Embedded Signup que usamos emite token com validade de 60 dias, e
# o Chatwoot NÃO renova nada sozinho: a tela só oferece um botão "Reconfigurar",
# que exige uma pessoa refazendo o fluxo com a Meta.
#
# Pior: o Chatwoot NEM SABE quando o token morre. O
# Whatsapp::ChannelCreationService grava em provider_config apenas api_key,
# phone_number_id, business_account_id e source — o `expires_in` que veio na
# troca do código é DESCARTADO. Não há coluna de validade no channel_whatsapp.
#
# O único aviso que existe é reativo: o concern Reauthorizable conta as falhas
# de API e, na SEGUNDA, marca a caixa e manda "WhatsApp desconectado" para os
# administradores da conta. Isso chega DEPOIS de as mensagens já estarem
# falhando — o cliente descobre pelo cliente dele.
#
# Este script fecha essa lacuna pelo único caminho confiável: pergunta a
# validade à PRÓPRIA META, via /debug_token, em vez de tentar adivinhar 60 dias
# a partir da data de criação da caixa (que erra sempre que alguém reconfigura).
#
# ⚠️ NÃO IMPRIME TOKEN. Nem em erro, nem em depuração. O que aparece no log é
# telefone, conta e prazo.

require 'net/http'
require 'json'

DIAS_ALERTA = Integer(ENV.fetch('DIAS_ALERTA', 14))   # avisa a partir daqui
DIAS_CRITICO = Integer(ENV.fetch('DIAS_CRITICO', 5))  # aqui já é incidente
VERSAO_API = 'v22.0'.freeze

APP_ID = ENV['WHATSAPP_APP_ID'].to_s
APP_SECRET = ENV['WHATSAPP_APP_SECRET'].to_s

if APP_ID.empty? || APP_SECRET.empty?
  warn 'ERRO: WHATSAPP_APP_ID/WHATSAPP_APP_SECRET ausentes no ambiente.'
  warn 'Sem eles não dá para consultar a Meta. Conferir o env_file do compose.'
  exit 1
end

# O app access token é literalmente "id|secret" — é assim que a Meta espera.
TOKEN_DO_APP = "#{APP_ID}|#{APP_SECRET}".freeze

def consulta_meta(token_do_canal)
  uri = URI("https://graph.facebook.com/#{VERSAO_API}/debug_token")
  uri.query = URI.encode_www_form(input_token: token_do_canal, access_token: TOKEN_DO_APP)
  resposta = Net::HTTP.get_response(uri)
  corpo = JSON.parse(resposta.body)
  return { erro: corpo.dig('error', 'message') || "HTTP #{resposta.code}" } unless resposta.is_a?(Net::HTTPSuccess)

  corpo['data'] || { erro: 'resposta sem campo data' }
rescue StandardError => e
  { erro: "#{e.class}: #{e.message}" }
end

canais = Channel::Whatsapp.where(provider: 'whatsapp_cloud')

puts '── vigia do token do WhatsApp ─────────────'
puts format('  canais whatsapp_cloud: %d  ·  alerta em %d dias, crítico em %d',
            canais.count, DIAS_ALERTA, DIAS_CRITICO)
puts

if canais.empty?
  # Não é sucesso nem erro: é a verdade de hoje. Sair 0 e dizer o motivo.
  puts 'Nenhum canal conectado ainda — nada a vigiar.'
  puts 'O vigia já fica de pé: quando o primeiro número entrar, ele passa a ver.'
  exit 0
end

alertas = []
falhas = []

canais.find_each do |canal|
  conta = canal.account&.name || "conta ##{canal.account_id}"
  rotulo = "#{canal.phone_number} (#{conta})"

  token = canal.provider_config['api_key'].to_s
  if token.empty?
    falhas << "#{rotulo}: sem token gravado no provider_config"
    puts format('  %-32s SEM TOKEN', rotulo)
    next
  end

  dados = consulta_meta(token)

  if dados[:erro]
    falhas << "#{rotulo}: #{dados[:erro]}"
    puts format('  %-32s ERRO ao consultar a Meta: %s', rotulo, dados[:erro])
    next
  end

  # A Meta responde is_valid=false para token já morto ou revogado.
  unless dados['is_valid']
    motivo = dados.dig('error', 'message') || 'token inválido ou revogado'
    alertas << "#{rotulo}: JÁ EXPIRADO — #{motivo}"
    puts format('  %-32s JÁ EXPIRADO (%s)', rotulo, motivo)
    next
  end

  expira_em = dados['expires_at'].to_i

  # expires_at = 0 significa que NÃO expira. É o cenário que queremos, e vale
  # registrar: se um dia trocarmos para um modelo sem expiração, é aqui que se
  # confirma — em vez de acreditar no que o painel da Meta prometeu.
  if expira_em.zero?
    puts format('  %-32s não expira ✅', rotulo)
    next
  end

  data = Time.at(expira_em)
  dias = ((data - Time.current) / 86_400).floor

  situacao = if dias <= DIAS_CRITICO then 'CRÍTICO'
             elsif dias <= DIAS_ALERTA then 'atenção'
             else 'ok'
             end
  puts format('  %-32s %-8s %d dias (até %s)', rotulo, situacao, dias, data.strftime('%d/%m/%Y'))

  next if dias > DIAS_ALERTA

  alertas << "#{rotulo}: expira em #{dias} dia(s), em #{data.strftime('%d/%m/%Y')}"
end

# ── Avisar gente, não só o log ─────────────────────────────────────────────
# Log que ninguém lê não é alerta. O e-mail vai para os administradores gerais,
# que o admins-gerais.rb garante existirem em todas as empresas.
if alertas.any? || falhas.any?
  destinos = User.joins(:account_users)
                 .where(account_users: { role: :administrator })
                 .distinct.pluck(:email)
                 .select { |e| e.end_with?('@apollosolution.com.br') }

  corpo = []
  corpo << 'Vigia do token do WhatsApp — ApolloDesk'
  corpo << ''
  if alertas.any?
    corpo << 'TOKENS PERTO DE EXPIRAR (ou já expirados):'
    alertas.each { |a| corpo << "  - #{a}" }
    corpo << ''
    corpo << 'O Chatwoot NAO renova sozinho. Para renovar: Configuracoes ->'
    corpo << 'Caixas de entrada -> a caixa -> Reconfigurar, e refazer o fluxo'
    corpo << 'com a Meta. Depois do prazo, as mensagens param de sair.'
    corpo << ''
  end
  if falhas.any?
    corpo << 'CANAIS QUE NAO DEU PARA CONFERIR:'
    falhas.each { |f| corpo << "  - #{f}" }
    corpo << ''
    corpo << 'Nao conseguir conferir nao e o mesmo que estar ok.'
    corpo << ''
  end
  corpo << "Conferido em #{Time.current.strftime('%d/%m/%Y %H:%M')}."

  if destinos.any?
    ActionMailer::Base.mail(
      to: destinos,
      from: ENV.fetch('MAILER_SENDER_EMAIL', 'contato@apollosolution.com.br'),
      subject: "[ApolloDesk] Token do WhatsApp: #{alertas.size} alerta(s), #{falhas.size} falha(s)",
      body: corpo.join("\n")
    ).deliver_now
    puts
    puts "  e-mail enviado para: #{destinos.join(', ')}"
  else
    puts
    puts '  ⚠️ nenhum administrador @apollosolution.com.br encontrado — e-mail NAO enviado'
  end
end

# ── Sair com o código certo ────────────────────────────────────────────────
# Exit != 0 para o cron reclamar. Nesta stack falha silenciosa é o padrão, e um
# vigia que sempre sai 0 é um vigia que não vigia.
puts
if alertas.any? || falhas.any?
  puts "ATENÇÃO: #{alertas.size} alerta(s), #{falhas.size} falha(s) de consulta."
  exit 1
end
puts "OK: os #{canais.count} canal(is) estão com token folgado."
