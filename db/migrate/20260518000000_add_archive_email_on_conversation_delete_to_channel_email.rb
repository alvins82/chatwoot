class AddArchiveEmailOnConversationDeleteToChannelEmail < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_email, :archive_email_on_conversation_delete, :boolean, default: false, null: false
  end
end
