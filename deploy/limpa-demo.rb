# ApolloDesk — remove TUDO que o seed-demo.rb criou, e só isso.
#
# Rodar: docker exec apollo-desk-rails bundle exec rails runner /tmp/limpa-demo.rb
#
# Existe desde o primeiro dia de propósito: dado de demonstração que não tem
# como sair vira dado de produção por inércia. O critério de remoção é o mesmo
# que o seed usa para marcar — additional_attributes['demo'] ou o prefixo
# [demo]/demo- no nome — então nada real é levado junto.

account = Account.first
abort 'Nenhuma conta encontrada.' if account.nil?

antes = {
  conversas: Conversation.where(account: account).count,
  contatos:  Contact.where(account: account).count,
  caixas:    Inbox.where(account: account).count
}

demo_inboxes = Inbox.where(account: account).where("name like '[demo]%'")
demo_contatos = Contact.where(account: account).where("additional_attributes->>'demo' = 'true'")

# Conversas e mensagens saem junto com a caixa/contato (dependent: :destroy),
# mas apago explicitamente para o caso de alguma ter sido movida de caixa.
Conversation.where(account: account)
            .where("inbox_id in (?) or contact_id in (?)", demo_inboxes.ids, demo_contatos.ids)
            .find_each(&:destroy!)

demo_inboxes.find_each(&:destroy!)
demo_contatos.find_each(&:destroy!)

# ⚠️ NOTIFICAÇÕES ÓRFÃS — o defeito que apareceu no lab em 28/ago/2026.
#
# A tabela `notifications` guarda o ponteiro para a conversa em
# primary_actor_id, SEM chave estrangeira. Apagar conversa por SQL (ou por
# qualquer caminho que não passe pelos callbacks) deixa a notificação para
# trás apontando para o nada.
#
# O estrago não é cosmético: o CONTADOR da Caixa de Entrada soma as linhas e
# continua marcando "11 não lidas", mas UM item que não consegue resolver a
# conversa derruba a renderização da lista inteira — a tela fica vazia com o
# badge cheio, e não há erro visível para explicar. Foi exatamente o que o
# Leonardo viu.
orfas = Notification.where(primary_actor_type: 'Conversation')
                    .where.not(primary_actor_id: Conversation.select(:id))
puts "  notificações órfãs removidas: #{orfas.count}" if orfas.any?
orfas.destroy_all
Label.where(account: account).where("title like 'demo-%'").find_each(&:destroy!)
Team.where(account: account).where("name like '[demo]%'").find_each(&:destroy!)
CannedResponse.where(account: account).where("short_code like 'demo-%'").find_each(&:destroy!)
User.where("email like 'demo.%@apollosolution.com.br'").find_each(&:destroy!)

depois = {
  conversas: Conversation.where(account: account).count,
  contatos:  Contact.where(account: account).count,
  caixas:    Inbox.where(account: account).count
}

puts '── removido ───────────────────────────────'
antes.each_key { |k| puts format('  %-10s %d -> %d', k, antes[k], depois[k]) }
puts 'OK: nada de demo restou.' if depois.values.all?(&:zero?)
