# ApolloDesk — prova que o envio de e-mail FUNCIONA de verdade.
#
# Rodar:  docker exec apollo-desk-rails bundle exec rails runner /tmp/testa-smtp.rb
#         (opcional) PARA=alguem@dominio.com para escolher o destinatário
#
# POR QUE ESTE SCRIPT EXISTE
# --------------------------
# Conferir as variáveis do .env não prova nada: com credencial errada, host
# errado ou porta sem quem escute, o Chatwoot aceita o convite de agente, mostra
# "convite enviado" na tela e o e-mail nunca sai. É a falha silenciosa padrão
# desta stack. A única prova é entregar uma mensagem.

destino = ENV['PARA'].presence || 'leonardo@apollosolution.com.br'
cfg = ActionMailer::Base.smtp_settings

puts '── configuração em uso ────────────────────'
puts format('  %-22s %s', 'entrega', ActionMailer::Base.delivery_method)
%i[address port domain user_name authentication tls ssl enable_starttls_auto].each do |k|
  next unless cfg.key?(k)

  puts format('  %-22s %s', k, cfg[k])
end
puts format('  %-22s %s', 'password', cfg[:password].present? ? '[definida]' : '*** VAZIA ***')
puts format('  %-22s %s', 'remetente', ENV.fetch('MAILER_SENDER_EMAIL', '(não definido)'))

if ActionMailer::Base.delivery_method == :sendmail
  puts
  puts 'ERRO: SMTP_ADDRESS está vazio, então o Chatwoot caiu no sendmail local —'
  puts '      que não existe neste container. Nenhum e-mail sai. Configure o .env.'
  exit 1
end

if cfg[:password].blank?
  puts
  puts 'ERRO: SMTP_PASSWORD vazia. A conta apollodesk@apollosolution.com.br existe'
  puts '      no Stalwart, mas a senha precisa ser definida no console do ApolloMail'
  puts '      e gravada em /root/plan-secrets/apollo-desk.env.'
  exit 1
end

puts
puts "── enviando para #{destino} ──────────────"
begin
  ActionMailer::Base.mail(
    to: destino,
    from: ENV.fetch('MAILER_SENDER_EMAIL', 'apollodesk@apollosolution.com.br'),
    subject: '[ApolloDesk] teste de envio',
    body: "Se esta mensagem chegou, o SMTP do ApolloDesk está funcionando.\n\n" \
          "Enviada em #{Time.current} pelo deploy/testa-smtp.rb.\n"
  ).deliver_now
  puts 'OK: mensagem entregue ao servidor sem erro.'
  puts '⚠️  Isso prova que o SMTP aceitou. CONFIRMAR NA CAIXA que chegou —'
  puts '    aceite do servidor não é entrega na caixa (SPF/DKIM/spam ainda contam).'
rescue StandardError => e
  puts "ERRO no envio: #{e.class} — #{e.message}"
  puts
  puts 'Pistas comuns:'
  puts '  535/authentication  → senha errada ou conta sem senha definida'
  puts '  Connection refused  → porta errada (o Stalwart NÃO escuta na 587; usar 465)'
  puts '  SSL/wrong version   → SMTP_TLS=false com porta 465, ou STARTTLS na porta errada'
  exit 1
end
