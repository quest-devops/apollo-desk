# ApolloDesk — espelho das respostas na caixa de e-mail (pasta Enviados).
#
# O PEDIDO (Leonardo, 26/out/2026)
# --------------------------------
# "O webmail é a fonte da verdade, o Desk deve ser um espelhamento dele, assim
# como o WhatsApp." No WhatsApp isso é de graça: o aparelho guarda tudo, mandando
# ou recebendo. No e-mail, não — o Chatwoot responde por SMTP e NUNCA grava cópia
# na caixa. Medido em contato@dagostinopapelaria.com.br: Entrada com 34 mensagens,
# Enviados ZERADA. Quem abrisse a caixa veria só as perguntas, nunca as respostas.
#
# O QUE ISTO FAZ
# --------------
# Depois de CADA envio bem-sucedido, grava (IMAP APPEND) a mensagem exata que saiu
# na pasta Enviados da própria caixa, marcada como lida. A caixa volta a conter a
# conversa inteira, e o webmail agrupa certo porque o Message-ID, o In-Reply-To e o
# References são os mesmos que foram para o destinatário (por isso gravamos
# `mail.encoded`, e não uma mensagem remontada).
#
# POR QUE OBSERVER, E NÃO UM PATCH NO MAILER
# ------------------------------------------
# `delivered_email` é chamado pelo ActionMailer DEPOIS da entrega — só grava o que
# de fato saiu, e não precisa de âncora em código do upstream (ao contrário dos
# outros patches daqui, este não quebra quando o Chatwoot muda de versão).
#
# ⚠️ ERRO AQUI NUNCA PODE SUBIR. Quando este código roda, o SMTP JÁ ENTREGOU a
# mensagem. Uma exceção faria o job do Sidekiq falhar e ser repetido — e o cliente
# receberia a resposta DUAS VEZES. Por isso todo o corpo é `rescue StandardError`:
# falhou ao espelhar, registra no log e segue.
#
# Alcance: só canais de e-mail com IMAP e SMTP próprios (hoje contato@ da Dagostino;
# o canal de demonstração tem smtp desligado e é ignorado). Não toca em WhatsApp.
module ApolloEspelhoEnviados
  TIMEOUT = 15

  def self.delivered_email(mail)
    canal = canal_de(mail)
    return if canal.nil?

    grava_em_enviados(canal, mail)
  rescue StandardError => e
    # Ver o aviso acima: engolir é proposital.
    Rails.logger.error("[APOLLO_ESPELHO] falhou ao espelhar #{mail&.message_id}: #{e.class}: #{e.message}")
  end

  # Só espelha quando o remetente É uma caixa nossa com credencial própria.
  def self.canal_de(mail)
    endereco = Mail::Address.new(Array(mail.from).first.to_s).address
    return nil if endereco.blank?

    canal = Channel::Email.find_by(email: endereco)
    return nil unless canal&.imap_enabled && canal.smtp_enabled

    canal
  rescue StandardError
    nil
  end

  def self.grava_em_enviados(canal, mail)
    # ⚠️ Só `open_timeout` aqui: o net-imap desta imagem recusa `read_timeout`
    # no construtor com `ArgumentError: invalid config options` (medido em
    # produção, 26/out/2026 — o rescue segurou e o envio não foi afetado).
    imap = Net::IMAP.new(canal.imap_address, port: canal.imap_port, ssl: canal.imap_enable_ssl,
                                             open_timeout: TIMEOUT)
    begin
      imap.login(canal.imap_login, canal.imap_password)
      pasta = pasta_enviados(imap)
      imap.append(pasta, mail.encoded, [:Seen], Time.now)
      Rails.logger.info("[APOLLO_ESPELHO] #{mail.message_id} gravada em '#{pasta}' de #{canal.email}")
    ensure
      encerra(imap)
    end
  end

  # A pasta de enviados tem nome diferente em cada servidor ("Sent Items" no
  # Stalwart, "Sent" em outros). O nome certo vem do atributo \Sent do próprio
  # servidor (RFC 6154); a lista fixa é só rede de segurança.
  def self.pasta_enviados(imap)
    pastas = imap.list('', '*') || []
    especial = pastas.find { |p| p.attr.include?(:Sent) }
    return especial.name if especial

    nomes = pastas.map(&:name)
    (nomes & ['Sent Items', 'Sent', 'INBOX.Sent', 'Enviados']).first || 'Sent'
  end

  def self.encerra(imap)
    imap.logout
  rescue StandardError
    imap.disconnect
  end
end

Rails.application.config.after_initialize do
  ActionMailer::Base.register_observer(ApolloEspelhoEnviados)
end
