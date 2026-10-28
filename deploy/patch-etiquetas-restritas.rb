# ApolloDesk — etiquetas restritas: algumas etiquetas só podem ser vistas, aplicadas e
# removidas por usuários específicos. Roda no BUILD da imagem (ver Dockerfile).
#
# O PEDIDO (Leonardo, 26/out/2026)
# --------------------------------
# Na Dagostino, as etiquetas "corp-*" (carteiras) só podem ser usadas pelo Roberto.
# ("clientes-corporativo" é de todos — padrão ancorado em ^corp-, 28/out/2026.)
# O Chatwoot não tem isso: etiqueta é da conta inteira, qualquer agente aplica
# qualquer uma (a edição Enterprise tem papéis, mas nunca por etiqueta).
#
# COMO FICA
# ---------
# A regra mora nos custom_attributes da CONTA (dado, não código):
#   account.custom_attributes['etiquetas_restritas'] =
#     [ { 'padrao' => '^corp-', 'usuarios' => [41] } ]      # regex (sem distinguir maiúsculas) + ids de usuário
# Quem pode: os ids listados e qualquer usuário @apollosolution.com.br (quem opera o Desk
# precisa enxergar a etiqueta em Configurações › Etiquetas). Todo o resto NÃO VÊ a etiqueta:
#   1. GET /labels (índice) filtra as restritas → somem do seletor da conversa, da barra
#      lateral, dos filtros e de Configurações › Etiquetas;
#   2. POST /conversations/:id/labels e /contacts/:id/labels (LabelConcern#create) PRESERVAM
#      as restritas que a conversa já tem e DESCARTAM as que o usuário tentar incluir —
#      necessário porque a tela manda a lista inteira, e um agente que não vê a etiqueta
#      a apagaria sem querer ao mexer nas outras.
# Etiqueta nova cujo nome case com o padrão já nasce restrita. Conversa com etiqueta
# restrita mostra as outras normalmente (o front só exibe títulos que existem no índice).
#
# ⚠️ Ao subir de versão do Chatwoot: as duas âncoras abaixo precisam continuar existindo;
# o build FALHA se sumirem, de propósito.
require 'fileutils'

APP = '/app'.freeze

MODULO = <<~'RUBY'
  # ApolloDesk — etiquetas restritas por usuário. Ver deploy/patch-etiquetas-restritas.rb.
  module ApolloEtiquetasRestritas
    DOMINIO_OPERADOR = '@apollosolution.com.br'.freeze

    def self.regras(account)
      Array(account&.custom_attributes.to_h['etiquetas_restritas']).filter_map do |r|
        padrao = r['padrao'].to_s
        next if padrao.empty?

        { re: Regexp.new(padrao, Regexp::IGNORECASE), usuarios: Array(r['usuarios']).map(&:to_i) }
      end
    rescue RegexpError
      []
    end

    # A etiqueta é restrita PARA ESTE usuário? (regra bate no título e ele não está na lista)
    def self.restrita?(account, user, titulo)
      return false if user && user.email.to_s.downcase.end_with?(DOMINIO_OPERADOR)

      regras(account).any? { |r| r[:re].match?(titulo.to_s) && !(user && r[:usuarios].include?(user.id)) }
    end

    def self.visiveis(account, user, labels)
      labels.reject { |l| restrita?(account, user, l.respond_to?(:title) ? l.title : l) }
    end

    # Lista final a gravar: o que o usuário mandou, menos as restritas que ele não pode;
    # mais as restritas que a conversa/contato JÁ tinha (ele não as vê, não pode apagá-las).
    def self.preserva(account, user, atuais, novas)
      atuais = Array(atuais).map(&:to_s)
      novas = Array(novas).map(&:to_s)
      pode, nao_pode = novas.partition { |t| !restrita?(account, user, t) }
      mantidas = atuais.select { |t| restrita?(account, user, t) }
      Rails.logger.info("[etiquetas-restritas] #{user&.email} tentou aplicar #{nao_pode.inspect} — descartado") if nao_pode.any?
      (pode + mantidas).uniq
    end
  end
RUBY

File.write("#{APP}/app/models/concerns/apollo_etiquetas_restritas.rb", MODULO)

def troca(arquivo, antes, depois)
  caminho = "#{APP}/#{arquivo}"
  src = File.read(caminho)
  abort("patch-etiquetas-restritas: âncora não encontrada em #{arquivo}:\n#{antes}") unless src.include?(antes)
  File.write(caminho, src.sub(antes, depois))
  puts "patch-etiquetas-restritas: #{arquivo} ok"
end

troca('app/controllers/concerns/label_concern.rb',
      "    model.update_labels(permitted_params[:labels])\n",
      "    model.update_labels(ApolloEtiquetasRestritas.preserva(Current.account, Current.user, model.label_list, permitted_params[:labels]))\n")

troca('app/controllers/api/v1/accounts/labels_controller.rb',
      "    @labels = policy_scope(Current.account.labels)\n",
      "    @labels = ApolloEtiquetasRestritas.visiveis(Current.account, Current.user, policy_scope(Current.account.labels))\n")

puts 'patch-etiquetas-restritas: módulo gravado em app/models/concerns/apollo_etiquetas_restritas.rb'
