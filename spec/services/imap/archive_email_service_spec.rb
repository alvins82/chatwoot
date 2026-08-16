require 'rails_helper'

RSpec.describe Imap::ArchiveEmailService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:message_id) { '<msg-1@example.com>' }

  before do
    allow(Net::IMAP).to receive(:new).with(
      channel.imap_address, port: channel.imap_port, ssl: channel.imap_enable_ssl
    ).and_return(imap)
    allow(imap).to receive(:authenticate).with('plain', channel.imap_login, channel.imap_password)
    allow(imap).to receive(:select).with('INBOX')
    allow(imap).to receive(:logout)
  end

  describe '#perform' do
    it 'finds the message by Message-ID and archives it from INBOX' do
      allow(imap).to receive(:uid_search).with(['HEADER', 'Message-ID', message_id]).and_return([42])
      allow(imap).to receive(:uid_store).with([42], '+FLAGS', [:Deleted])
      allow(imap).to receive(:expunge)

      result = described_class.new(channel: channel, message_ids: [message_id]).perform

      expect(imap).to have_received(:select).with('INBOX')
      expect(imap).to have_received(:uid_search).with(['HEADER', 'Message-ID', message_id])
      expect(imap).to have_received(:uid_store).with([42], '+FLAGS', [:Deleted])
      expect(imap).to have_received(:expunge)
      expect(result).to eq([message_id])
    end

    it 'skips message-ids not found in INBOX without storing flags' do
      allow(imap).to receive(:uid_search).with(['HEADER', 'Message-ID', message_id]).and_return([])
      allow(imap).to receive(:uid_store)
      allow(imap).to receive(:expunge)

      result = described_class.new(channel: channel, message_ids: [message_id]).perform

      expect(imap).not_to have_received(:uid_store)
      expect(imap).not_to have_received(:expunge)
      expect(result).to eq([])
    end

    it 'returns [] and does not open a connection when message_ids is empty' do
      allow(Net::IMAP).to receive(:new)

      result = described_class.new(channel: channel, message_ids: []).perform

      expect(result).to eq([])
      expect(Net::IMAP).not_to have_received(:new)
    end

    context 'with a Microsoft (OAuth) channel' do
      let(:channel) { create(:channel_email, :microsoft_email, account: account) }
      let(:token_service) { instance_double(Microsoft::RefreshOauthTokenService, access_token: 'oauth-token') }

      before do
        allow(Microsoft::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(token_service)
        allow(imap).to receive(:authenticate).with('XOAUTH2', channel.imap_login, 'oauth-token')
      end

      it 'authenticates with XOAUTH2 using the refreshed token' do
        allow(imap).to receive(:uid_search).and_return([7])
        allow(imap).to receive(:uid_store)
        allow(imap).to receive(:expunge)

        described_class.new(channel: channel, message_ids: [message_id]).perform

        expect(imap).to have_received(:authenticate).with('XOAUTH2', channel.imap_login, 'oauth-token')
      end
    end

    context 'with a Google (OAuth) channel' do
      let(:channel) { create(:channel_email, :imap_email, account: account, provider: 'google') }
      let(:token_service) { instance_double(Google::RefreshOauthTokenService, access_token: 'oauth-token') }

      before do
        allow(Google::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(token_service)
        allow(imap).to receive(:authenticate).with('XOAUTH2', channel.imap_login, 'oauth-token')
      end

      it 'archives via IMAP MOVE to [Gmail]/All Mail rather than +FLAGS \\Deleted + EXPUNGE' do
        allow(imap).to receive(:uid_search).with(['HEADER', 'Message-ID', message_id]).and_return([42])
        allow(imap).to receive(:uid_move).with([42], '[Gmail]/All Mail')
        allow(imap).to receive(:uid_store)
        allow(imap).to receive(:expunge)

        result = described_class.new(channel: channel, message_ids: [message_id]).perform

        expect(imap).to have_received(:uid_move).with([42], '[Gmail]/All Mail')
        expect(imap).not_to have_received(:uid_store)
        expect(imap).not_to have_received(:expunge)
        expect(result).to eq([message_id])
      end
    end
  end
end
