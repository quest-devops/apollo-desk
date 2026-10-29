# ApolloDesk — campanhas de WhatsApp rastreáveis: mensagem real na conversa + relatório por campanha.
# Roda no BUILD da imagem (ver Dockerfile). Pedido do Leonardo (28/out/2026), E16 da APOLLO-132.
#
# O QUE O CHATWOOT 4.17.1 (edição MIT) FAZ
# ----------------------------------------
# - A campanha one-off de WhatsApp chama a API da Meta uma vez por contato e DESCARTA a resposta:
#   não grava mensagem, não cria conversa, não guarda o id do envio. O status que a Meta devolve
#   depois (entregue/lido/falhou) não acha mensagem e é ignorado. "Concluída" só quer dizer que a
#   lista foi percorrida — uma campanha com 0 entregas aparece igual a uma com 100%.
# - A TELA de relatório (routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue, MIT)
#   existe no front, mas o botão que leva a ela é escondido (isEnterprise) e o backend que a
#   alimenta (campaign_recipients, controller de analytics) está em enterprise/, sob a licença
#   comercial da Chatwoot — não usamos nada de lá.
#
# O QUE ESTE PATCH FAZ (código nosso, MIT)
# ----------------------------------------
# 1. Whatsapp::OneoffCampaignService#process_contact passa a chamar ApolloCampanhas.enviar: cria a
#    conversa do contato (já RESOLVIDA, para não entupir a fila da equipe nem acordar o bot) e uma
#    mensagem de saída de verdade com template_params + campaign_id. O envio segue o mesmo caminho do
#    modelo enviado à mão (SendReplyJob → SendOnWhatsappService), então o Chatwoot grava o source_id
#    e casa os status da Meta sozinho: o balão mostra entregue/lido/falhou com o motivo, e a resposta
#    do cliente cai na mesma conversa (reabre).
# 2. Módulo ApolloCampanhas: métricas e lista por contato calculadas a partir dessas mensagens
#    (audiência = contatos das etiquetas; na fila / pulado / enviado / entregue / lido / falhou /
#    RESPONDEU), com os códigos de erro da Meta traduzidos.
# 3. Controller Api::V1::Accounts::Campaigns::ApolloAnalyticsController nas MESMAS rotas que o front
#    já chama (analytics/metrics e analytics/contacts) + exportação CSV (?formato=csv).
# 4. public/apollodesk/campanhas.js (copiado pelo Dockerfile) + <script> no layout da SPA: mostra o
#    botão do relatório nos cards, traduz a tela para pt-BR, acrescenta o card "Responderam" e o
#    botão "Exportar CSV".
#
# ⚠️ Ao subir de versão: o build FALHA se qualquer âncora sumir, de propósito.
require 'fileutils'

APP = '/app'.freeze

MODULO = <<~'RUBY'
  # ApolloDesk — campanhas de WhatsApp rastreáveis. Ver deploy/patch-campanhas.rb.
  module ApolloCampanhas
    STATUS = %w[queued skipped sent delivered read failed].freeze

    # Códigos da Meta (https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes) em português.
    MOTIVOS = {
      '131048' => 'Limite diário de conversas do número atingido (empresa sem verificação na Meta → 250 por 24 h)',
      '131049' => 'A Meta limitou mensagens de marketing para este usuário (engajamento)',
      '130472' => 'O número do destinatário participa de um experimento da Meta (marketing bloqueado)',
      '131026' => 'Número não entregável: sem WhatsApp, versão antiga do app ou bloqueou a empresa',
      '131053' => 'Mídia inválida: a URL do cabeçalho não devolve a imagem/arquivo (devolve página ou erro)',
      '131042' => 'Problema de pagamento na conta WhatsApp Business (forma de pagamento)',
      '131047' => 'Mais de 24 h sem resposta do cliente: só modelo aprovado pode ser enviado',
      '131051' => 'Tipo de mensagem não suportado',
      '131056' => 'Muitas mensagens para o mesmo número em pouco tempo',
      '131000' => 'Erro genérico da Meta ao enviar',
      '130429' => 'Limite de taxa de envio da Meta atingido (muitas mensagens por segundo)',
      '132000' => 'Quantidade de parâmetros diferente do modelo aprovado',
      '132001' => 'Modelo não existe no idioma informado',
      '132012' => 'Formato dos parâmetros não confere com o modelo',
      '132015' => 'Modelo pausado pela Meta (qualidade baixa)',
      '132016' => 'Modelo desativado pela Meta',
      '133010' => 'Número não registrado na API',
      '100' => 'Parâmetro inválido na chamada à Meta',
      '190' => 'Token do WhatsApp expirou ou foi revogado',
      '368' => 'Conta WhatsApp Business temporariamente bloqueada por violação de política'
    }.freeze

    # ---- envio (chamado pelo OneoffCampaignService no lugar de channel.send_template) ----
    # Etiqueta que tira o contato de QUALQUER campanha (quem bloqueou, pediu para sair ou nunca comprou).
    ETIQUETA_BLOQUEIO = 'nao-enviar'.freeze

    def self.enviar(campaign, contact, template_params)
      if contact.label_list.map(&:to_s).include?(ETIQUETA_BLOQUEIO)
        Rails.logger.info("[apollo-campanhas] campanha #{campaign.id}: contato #{contact.id} pulado (#{ETIQUETA_BLOQUEIO})")
        return
      end
      inbox = campaign.inbox
      contact_inbox = contact.contact_inboxes.find_by(inbox_id: inbox.id) ||
                      ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
      raise 'não foi possível criar o contact_inbox' if contact_inbox.blank?

      conversation = ::Conversation.create!(
        account_id: campaign.account_id, inbox_id: inbox.id, contact_id: contact.id,
        contact_inbox_id: contact_inbox.id, campaign_id: campaign.id,
        additional_attributes: { 'apollo_campanha' => campaign.title }
      )
      # Nasce resolvida: fora da fila da equipe e do bot (o Chatwoot cria pendente quando a caixa tem
      # bot). update_columns de propósito: sem evento de mudança de status. A resposta do cliente reabre.
      limpa = { status: ::Conversation.statuses[:resolved] }
      limpa[:ai_assignee_id] = nil if ::Conversation.column_names.include?('ai_assignee_id')
      limpa[:ai_assignee_type] = nil if ::Conversation.column_names.include?('ai_assignee_type')
      conversation.update_columns(limpa) # rubocop:disable Rails/SkipsModelValidations

      conversation.messages.create!(
        account_id: campaign.account_id, inbox_id: inbox.id, message_type: :outgoing, content_type: :text,
        content: corpo(campaign, template_params), sender: campaign.sender,
        additional_attributes: { 'campaign_id' => campaign.id, 'template_params' => template_params }
      )
    rescue StandardError => e
      Rails.logger.error "[apollo-campanhas] campanha #{campaign.id} contato #{contact.id}: #{e.class} #{e.message}"
      nil
    end

    # Texto do balão: corpo do modelo aprovado com {{n}} preenchidos (+ a mídia do cabeçalho na 1ª linha).
    def self.corpo(campaign, tp)
      modelos = campaign.inbox.channel.try(:message_templates).to_a
      modelo = modelos.find { |m| m['name'] == tp['name'] && (tp['language'].blank? || m['language'] == tp['language']) } ||
               modelos.find { |m| m['name'] == tp['name'] }
      texto = modelo&.dig('components')&.find { |c| c['type'] == 'BODY' }&.dig('text').presence || campaign.message.to_s
      (tp.dig('processed_params', 'body') || {}).each { |k, v| texto = texto.gsub("{{#{k}}}", v.to_s) }
      header = tp.dig('processed_params', 'header')
      texto = "[#{header['media_type'] || 'mídia'}] #{header['media_url']}\n\n#{texto}" if header.is_a?(Hash) && header['media_url'].present?
      texto
    end

    # ---- relatório ----
    def self.audiencia(campaign)
      ids = Array(campaign.audience).select { |a| a['type'] == 'Label' }.map { |a| a['id'] }
      titulos = campaign.account.labels.where(id: ids).pluck(:title)
      return campaign.account.contacts.none if titulos.empty?

      campaign.account.contacts.tagged_with(titulos, any: true)
    end

    def self.mensagens(campaign)
      campaign.account.messages.where(message_type: :outgoing)
              .where("messages.additional_attributes->'campaign_id' = ?::jsonb", campaign.id.to_json)
    end

    # Uma linha por contato da audiência, com o status mais recente.
    def self.linhas(campaign)
      msgs = mensagens(campaign).order(created_at: :desc)
                                .pluck(:id, :conversation_id, :status, :source_id, :content_attributes, :content, :created_at)
      # Campanha concluída sem nenhuma mensagem = disparada antes do relatório existir: a tela mostra "indisponível".
      return [] if msgs.empty? && campaign.completed?

      conv_ids = msgs.map { |m| m[1] }.uniq
      conv = ::Conversation.where(id: conv_ids).pluck(:id, :contact_id, :display_id).each_with_object({}) { |(id, cid, did), h| h[id] = [cid, did] }
      respostas = ::Message.where(conversation_id: conv_ids, message_type: :incoming).group(:conversation_id).minimum(:created_at)
      contatos = ::Contact.where(id: conv.values.map(&:first)).pluck(:id, :name, :phone_number).each_with_object({}) { |(id, n, p), h| h[id] = [n, p] }
      vistos = {}
      linhas = []
      msgs.each do |_id, conv_id, status, source_id, atributos, content, criado|
        cid, did = conv[conv_id]
        next if cid.nil? || vistos[cid]

        erro = (atributos || {})['external_error'] # external_error é chave de content_attributes, não coluna

        vistos[cid] = true
        nome, fone = contatos[cid]
        status = ::Message.statuses.key(status) if status.is_a?(Integer)
        st = if status == 'failed' then 'failed'
             elsif source_id.blank? && status == 'sent' then 'queued'
             else status
             end
        codigo, titulo = erro.to_s.split(': ', 2)
        linhas << {
          contact: { id: cid, name: nome, phone_number: fone }, status: st, message_content: content,
          error_code: (codigo.presence if erro.present?), error_title: (titulo.presence || erro if erro.present?),
          error_message: (MOTIVOS[codigo.to_s] if erro.present?),
          responded: respostas[conv_id].present? && respostas[conv_id] > criado,
          conversation_display_id: did, sent_at: criado, accepted: source_id.present?
        }
      end
      # Audiência sem mensagem: sem telefone = pulado; com telefone = ainda na fila (ou não processado).
      bloqueados = campaign.account.contacts.tagged_with(ETIQUETA_BLOQUEIO).pluck(:id).to_set
      audiencia(campaign).where.not(id: vistos.keys).pluck(:id, :name, :phone_number).each do |cid, nome, fone|
        sem_fone = fone.blank?
        bloqueado = bloqueados.include?(cid)
        linhas << {
          contact: { id: cid, name: nome, phone_number: fone }, status: (sem_fone || bloqueado) ? 'skipped' : 'queued',
          message_content: nil, error_code: nil, error_title: nil,
          error_message: if bloqueado then "Contato com a etiqueta #{ETIQUETA_BLOQUEIO}"
                         elsif sem_fone then 'Contato sem telefone'
                         else (campaign.completed? ? 'Não processado pela campanha' : nil) end,
          responded: false, conversation_display_id: nil, sent_at: nil, accepted: false
        }
      end
      linhas
    end

    def self.metricas(campaign)
      l = linhas(campaign)
      c = l.group_by { |x| x[:status] }.transform_values(&:size)
      {
        audience: l.size,
        sent: l.count { |x| x[:accepted] },
        delivered: c['delivered'].to_i + c['read'].to_i,
        read: c['read'].to_i,
        failed: c['failed'].to_i,
        skipped: c['skipped'].to_i,
        responded: l.count { |x| x[:responded] },
        status_counts: STATUS.index_with { |s| c[s].to_i }
      }
    end

    ROTULOS = { 'queued' => 'Na fila', 'skipped' => 'Pulado', 'sent' => 'Enviado (aguardando entrega)',
                'delivered' => 'Entregue', 'read' => 'Lido', 'failed' => 'Falhou' }.freeze

    def self.csv(linhas)
      require 'csv'
      "﻿" + CSV.generate(col_sep: ';') do |csv|
        csv << ['Contato', 'Telefone', 'Status', 'Enviado em', 'Respondeu', 'Código Meta', 'Motivo', 'Conversa']
        linhas.each do |l|
          csv << [l[:contact][:name], l[:contact][:phone_number], ROTULOS[l[:status]] || l[:status],
                  l[:sent_at]&.in_time_zone('America/Sao_Paulo')&.strftime('%d/%m/%Y %H:%M'),
                  l[:responded] ? 'Sim' : 'Não', l[:error_code], l[:error_message] || l[:error_title],
                  l[:conversation_display_id]]
        end
      end
    end
  end
RUBY
File.write("#{APP}/app/models/concerns/apollo_campanhas.rb", MODULO)

CONTROLLER = <<~'RUBY'
  # ApolloDesk — relatório de campanha de WhatsApp (mesmas rotas que a tela do front chama).
  # Ver deploy/patch-campanhas.rb.
  class Api::V1::Accounts::Campaigns::ApolloAnalyticsController < Api::V1::Accounts::BaseController
    POR_PAGINA = 25

    before_action :campaign
    before_action { authorize @campaign, :show? }

    def metrics
      render json: ApolloCampanhas.metricas(@campaign)
    end

    def contacts
      linhas = ApolloCampanhas.linhas(@campaign)
      filtro = params[:status].to_s
      linhas = linhas.select { |l| l[:responded] } if filtro == 'responded'
      linhas = linhas.select { |l| l[:status] == filtro } if ApolloCampanhas::STATUS.include?(filtro)

      if params[:formato] == 'csv'
        send_data ApolloCampanhas.csv(linhas), filename: "campanha-#{@campaign.display_id}.csv", type: 'text/csv; charset=utf-8'
        return
      end

      pagina = Kaminari.paginate_array(linhas).page(params[:page].presence || 1).per(POR_PAGINA)
      render json: {
        payload: pagina.to_a,
        meta: { current_page: pagina.current_page, total_pages: pagina.total_pages, total_count: pagina.total_count }
      }
    end

    private

    def campaign
      @campaign ||= Current.account.campaigns.find_by!(display_id: params[:campaign_id])
    end
  end
RUBY
FileUtils.mkdir_p("#{APP}/app/controllers/api/v1/accounts/campaigns")
File.write("#{APP}/app/controllers/api/v1/accounts/campaigns/apollo_analytics_controller.rb", CONTROLLER)

def troca(arquivo, antes, depois)
  caminho = "#{APP}/#{arquivo}"
  src = File.read(caminho)
  abort("patch-campanhas: âncora não encontrada em #{arquivo}:\n#{antes}") unless src.include?(antes)
  File.write(caminho, src.sub(antes, depois))
  puts "patch-campanhas: #{arquivo} ok"
end

# 1) envio vira mensagem real
troca('app/services/whatsapp/oneoff_campaign_service.rb',
      "    send_whatsapp_template_message(to: contact.phone_number, template_params: processed_template_params)\n",
      "    ApolloCampanhas.enviar(campaign, contact, processed_template_params) # ApolloDesk: mensagem real na conversa (rastreável)\n")

# 3) rotas (as mesmas URLs que o front já chama; o bloco enterprise logo abaixo fica inerte)
troca('config/routes.rb',
      "          resources :campaigns, only: [:index, :create, :show, :update, :destroy] do\n",
      "          resources :campaigns, only: [:index, :create, :show, :update, :destroy] do\n" \
      "            get 'analytics/metrics', to: 'campaigns/apollo_analytics#metrics' # ApolloDesk\n" \
      "            get 'analytics/contacts', to: 'campaigns/apollo_analytics#contacts' # ApolloDesk\n")

# 4) layout da SPA
layout = "#{APP}/app/views/layouts/vueapp.html.erb"
html = File.read(layout)
abort('patch-campanhas: </head> não encontrado no layout') unless html.include?('</head>')
unless html.include?('campanhas.js')
  File.write(layout, html.sub('</head>', "    <script src=\"/apollodesk/campanhas.js\" defer></script>\n  </head>"))
end
abort('patch-campanhas: JS não está em public/apollodesk/') unless File.exist?("#{APP}/public/apollodesk/campanhas.js")
puts 'patch-campanhas: módulo + controller + serviço + rotas + layout ok'
