# ApolloDesk — padrão de notificações de usuário NOVO: todos os alertas push ligados,
# nenhum por e-mail, som ligado para todas as conversas. Roda no BUILD (ver Dockerfile).
#
# Pedido do Leonardo (26/out/2026): "deixe por padrão o push ativado, e todos os alertas
# ativados, exceto para e-mail". O Chatwoot nasce com só "atribuída a mim" (push e e-mail).
# Os usuários que já existiam foram ajustados no banco no mesmo dia; este patch cuida dos
# próximos (AccountUser#create_notification_setting + ui_settings do User).
#
# ⚠️ Push no navegador ainda depende de cada agente clicar em "Permitir" quando o site pedir
# — isto aqui liga os eventos; a assinatura do navegador é do agente.
APP = '/app'.freeze

def troca(arquivo, antes, depois)
  caminho = "#{APP}/#{arquivo}"
  src = File.read(caminho)
  abort("patch-notificacoes-padrao: âncora não encontrada em #{arquivo}:\n#{antes}") unless src.include?(antes)
  File.write(caminho, src.sub(antes, depois))
  puts "patch-notificacoes-padrao: #{arquivo} ok"
end

troca('app/models/account_user.rb',
      "    setting.selected_email_flags = [:email_conversation_assignment]\n    setting.selected_push_flags = [:push_conversation_assignment]\n",
      "    setting.selected_email_flags = [] # ApolloDesk: e-mail desligado por padrão\n    setting.selected_push_flags = NotificationSetting::PUSH_NOTIFICATION_FLAGS.values # ApolloDesk: todos os push\n" \
      "    user.update_columns(ui_settings: (user.ui_settings || {}).to_h.merge('enable_audio_alerts' => 'all', 'always_play_audio_alert' => true, 'alert_tone' => 'ding')) # ApolloDesk: som ligado\n")
