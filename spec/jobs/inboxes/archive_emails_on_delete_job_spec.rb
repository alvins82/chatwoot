require 'rails_helper'

RSpec.describe Inboxes::ArchiveEmailsOnDeleteJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:message_ids) { ['<a@example.com>'] }

  it 'delegates to Imap::ArchiveEmailService' do
    service = instance_double(Imap::ArchiveEmailService, perform: [])
    allow(Imap::ArchiveEmailService).to receive(:new).with(channel: channel, message_ids: message_ids).and_return(service)

    described_class.perform_now(channel, message_ids)

    expect(service).to have_received(:perform)
  end

  it 'does nothing when message_ids is blank' do
    allow(Imap::ArchiveEmailService).to receive(:new)

    described_class.perform_now(channel, [])

    expect(Imap::ArchiveEmailService).not_to have_received(:new)
  end
end
