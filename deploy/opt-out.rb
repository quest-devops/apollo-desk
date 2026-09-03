# ApolloDesk — opt-out de verdade: quem responde SAIR para de receber campanha.
#
# Rodar (cron, a cada 10 min — ver /root/opt-out.sh no apollo-prod):
#   docker exec apollo-desk-rails bundle exec rails runner /tmp/opt-out.rb
#
#   JANELA_H=24   quantas horas para trás olhar (idempotente: reprocessar não repete)
#   CONFIRMA=0    para NÃO responder ao contato (padrão: responde uma vez)
#   ENSAIO=1      só mostra o que faria
#
# POR QUE ISTO NÃO É UMA AUTOMAÇÃO NATIVA DO CHATWOOT
# --------------------------------------------------
# A campanha escolhe o público por RÓTULO DE CONTATO
# (account.contacts.tagged_with — oneoff_campaign_service.rb). A automação
# nativa tem `add_label`, mas ela rotula a CONVERSA (action_service.rb:40), não
# o contato. Uma regra "se contém SAIR então add_label opt-out" marcaria a
# conversa, a campanha seguinte ignoraria a marca e mandaria de novo. Isso é o
# pior cenário: a pessoa pediu para sair, recebeu de novo, denuncia — e a Meta
# derruba a qualidade do número do CLIENTE.
#
# O QUE ELE FAZ, por mensagem recebida que seja só um pedido de saída:
#   1. rotula o CONTATO com `opt-out` (é o que a campanha lê);
#   2. remove do contato todo rótulo `disparo-*` (público de campanha);
#   3. grava contact.custom_attributes['opt_out_at'] — a prova, e a trava de repetição;
#   4. responde UMA vez confirmando (dentro da janela de 24 h, texto livre é permitido).
#
# O importa-contatos.rb respeita o rótulo `opt-out`: reimportar a planilha não
# reabre quem saiu.
#
# O QUE CONTA COMO PEDIDO DE SAÍDA: a mensagem INTEIRA ser uma das palavras
# abaixo (com ou sem pontuação/acento). "quero sair da promoção" NÃO conta —
# é conversa, um atendente decide. Falso positivo aqui é pior que falso
# negativo: tira alguém que só estava conversando.

require 'set'

JANELA_H = Integer(ENV.fetch('JANELA_H', 24))
CONFIRMA = ENV.fetch('CONFIRMA', '1') != '0'
ENSAIO   = ENV['ENSAIO'].present?

PALAVRAS = %w[sair parar stop cancelar remover descadastrar pare].freeze
PADRAO   = /\A[\s[:punct:]]*(#{PALAVRAS.join('|')})[\s[:punct:]]*\z/i
RESPOSTA = 'Pronto: você não receberá mais mensagens nossas por aqui. ' \
           'Se mudar de ideia, é só nos escrever.'.freeze

def normaliza(texto)
  texto.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '') # tira acento: "saír" -> "sair"
end

desde = JANELA_H.hours.ago
puts "── opt-out ── janela: últimas #{JANELA_H} h#{ENSAIO ? '  [ENSAIO]' : ''}#{CONFIRMA ? '' : '  [sem confirmação]'}"

candidatas = Message.joins(:inbox)
                    .where(message_type: :incoming, private: false)
                    .where('messages.created_at >= ?', desde)
                    .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                    .where.not(content: [nil, ''])
                    .includes(:conversation, :inbox)

achadas = candidatas.select { |m| normaliza(m.content).match?(PADRAO) }
puts format('   mensagens recebidas no WhatsApp: %d · pedidos de saída: %d', candidatas.count, achadas.size)

processados = Set.new
feitos = repetidos = 0

achadas.each do |m|
  cv = m.conversation
  contato = cv.contact
  next if contato.nil?
  next unless processados.add?(contato.id) # uma vez por contato por rodada

  rotulos = contato.labels.map(&:name)
  ja = contato.custom_attributes.to_h['opt_out_at'].present? && rotulos.include?('opt-out')
  campanha = rotulos.select { |r| r.start_with?('disparo-') }
  tag = format('%s · %s · "%s" · %s', cv.account.name, contato.name, m.content.to_s[0, 20], m.created_at.strftime('%d/%m %H:%M'))

  if ja && campanha.empty?
    repetidos += 1
    puts "   = já tratado: #{tag}"
    next
  end

  puts "   #{ENSAIO ? '~' : '+'} opt-out: #{tag}#{campanha.any? ? "  (tira #{campanha.join(', ')})" : ''}"
  next if ENSAIO

  Label.find_or_create_by!(account: cv.account, title: 'opt-out') { |l| l.color = '#E54666' }
  contato.update_labels((rotulos - campanha + ['opt-out']).uniq)
  attrs = contato.custom_attributes.to_h
  primeira_vez = attrs['opt_out_at'].blank?
  attrs['opt_out_at'] ||= Time.current.iso8601
  contato.update!(custom_attributes: attrs)

  # Confirmação: só na primeira vez, para não virar eco a cada "sair".
  if CONFIRMA && primeira_vez
    Messages::MessageBuilder.new(nil, cv, { content: RESPOSTA, message_type: 'outgoing' }).perform
    puts '     ↳ confirmação enviada'
  end
  feitos += 1
end

# ── Conferir o EFEITO ──────────────────────────────────────────────────────
puts
unless ENSAIO
  puts '── conferindo ─────────────────────────────'
  achadas.map(&:conversation).map(&:contact).compact.uniq.each do |c|
    r = c.reload.labels.map(&:name)
    ok = r.include?('opt-out') && r.none? { |x| x.start_with?('disparo-') }
    puts format('   %-28s %s  rótulos: %s', c.name.to_s[0, 28], ok ? 'OK ' : 'ERRO', r.join(', '))
    exit 1 unless ok
  end
end
puts format('OK: %d contato(s) opt-out nesta rodada, %d já tratado(s).', feitos, repetidos)
