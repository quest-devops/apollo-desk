# ApolloDesk — variáveis nos modelos do WhatsApp: seletor na tela + resolução no envio por conversa.
# Roda no BUILD da imagem (ver Dockerfile). Pedido do Leonardo (26–27/out/2026), E14 da APOLLO-132.
#
# O QUE O CHATWOOT 4.17.1 FAZ
# ---------------------------
# - Campanha: o campo de cada variável é texto livre e o envio resolve Liquid ({{ contact.name }}…)
#   por contato (Whatsapp::LiquidTemplateProcessorService).
# - Conversa (janela "Templates do WhatsApp" quando a janela de 24 h fechou): texto livre e o
#   valor vai LITERAL para a Meta — "{{ contact.name }}" chegaria escrito no cliente.
#
# O QUE ESTE PATCH FAZ
# --------------------
# 1. public/apollodesk/variaveis-modelo.js (copiado pelo Dockerfile) + <script> no layout da SPA:
#    em todo <input> de variável (placeholder "Insira o valor para N" / "Digite um valor para N")
#    aparece um <select> com as variáveis padrão e "Personalizado (digitar)".
# 2. Conversa: Whatsapp::SendOnWhatsappService#template_params passa pelo ApolloVariaveisModelo,
#    que resolve Liquid com contact/agent/inbox/account + hora_atual/data_atual.
# 3. Campanha: os mesmos hora_atual/data_atual entram nos drops do LiquidTemplateProcessorService.
#
# ⚠️ Ao subir de versão: o build FALHA se qualquer âncora sumir, de propósito.
APP = '/app'.freeze

MODULO = <<~'RUBY'
  # ApolloDesk — resolve variáveis Liquid nos parâmetros de modelo enviados por CONVERSA.
  # Ver deploy/patch-variaveis-modelo.rb.
  module ApolloVariaveisModelo
    LIQUID_EXPRESSION = /\{\{\s*(.+?)\s*\}\}/

    module JsonEscapeFilter
      def json_escape(input)
        input.to_s.to_json[1..-2]
      end
    end

    def self.extras
      agora = Time.current.in_time_zone('America/Sao_Paulo')
      { 'hora_atual' => agora.strftime('%H:%M'), 'data_atual' => agora.strftime('%d/%m/%Y') }
    end

    def self.processa(template_params, conversation:, agent: nil)
      return template_params if template_params.blank?

      copia = template_params.deep_dup
      pp = copia['processed_params']
      return copia if pp.blank? || !pp.to_json.match?(LIQUID_EXPRESSION)

      drops = {
        'contact' => ContactDrop.new(conversation.contact),
        'agent' => (agent.is_a?(User) ? UserDrop.new(agent) : nil),
        'inbox' => InboxDrop.new(conversation.inbox),
        'account' => AccountDrop.new(conversation.account),
        'conversation' => ConversationDrop.new(conversation)
      }.compact.merge(extras)
      raw = pp.to_json
      rewritten = raw.gsub(LIQUID_EXPRESSION) { "{{ #{Regexp.last_match(1)} | json_escape }}" }
      rendered = Liquid::Template.parse(rewritten).render!(drops, filters: [JsonEscapeFilter])
      copia.merge('processed_params' => JSON.parse(rendered))
    rescue Liquid::Error, JSON::ParserError => e
      Rails.logger.warn("[variaveis-modelo] Liquid falhou na conversa #{conversation&.id}: #{e.message}")
      template_params
    end
  end
RUBY
File.write("#{APP}/app/models/concerns/apollo_variaveis_modelo.rb", MODULO)

def troca(arquivo, antes, depois)
  caminho = "#{APP}/#{arquivo}"
  src = File.read(caminho)
  abort("patch-variaveis-modelo: âncora não encontrada em #{arquivo}:\n#{antes}") unless src.include?(antes)
  File.write(caminho, src.sub(antes, depois))
  puts "patch-variaveis-modelo: #{arquivo} ok"
end

# 2) conversa
troca('app/services/whatsapp/send_on_whatsapp_service.rb',
      "  def template_params\n    message.additional_attributes && message.additional_attributes['template_params']\n  end\n",
      "  def template_params\n    tp = message.additional_attributes && message.additional_attributes['template_params']\n" \
      "    ApolloVariaveisModelo.processa(tp, conversation: message.conversation, agent: message.sender) # ApolloDesk: resolve {{ contact.name }} etc.\n  end\n")

# 3) campanha: hora_atual/data_atual
troca('app/services/whatsapp/liquid_template_processor_service.rb',
      "      'account' => AccountDrop.new(campaign.account)\n    }\n",
      "      'account' => AccountDrop.new(campaign.account)\n    }.merge(ApolloVariaveisModelo.extras) # ApolloDesk: hora_atual, data_atual\n")

# 1) layout da SPA
layout = "#{APP}/app/views/layouts/vueapp.html.erb"
html = File.read(layout)
abort('patch-variaveis-modelo: </head> não encontrado no layout') unless html.include?('</head>')
unless html.include?('variaveis-modelo.js')
  File.write(layout, html.sub('</head>', "    <script src=\"/apollodesk/variaveis-modelo.js\" defer></script>\n  </head>"))
end
abort('patch-variaveis-modelo: JS não está em public/apollodesk/') unless File.exist?("#{APP}/public/apollodesk/variaveis-modelo.js")
puts 'patch-variaveis-modelo: layout + módulo + conversa + campanha ok'
