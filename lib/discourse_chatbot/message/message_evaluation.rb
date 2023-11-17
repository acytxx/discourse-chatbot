# frozen_string_literal: true
module ::DiscourseChatbot

  class MessageEvaluation < EventEvaluation

    DIRECT_MESSAGE = "DirectMessage"

    def on_submission(submission)
      ::DiscourseChatbot.progress_debug_message("2. evaluation")

      chat_message = submission

      user = chat_message.user
      user_id = user.id
      channel_id = chat_message.chat_channel_id
      message_contents = chat_message.message
      in_reply_to_id = chat_message.in_reply_to_id

      over_quota = over_quota(user_id)

      bot_username = SiteSetting.chatbot_bot_user
      bot_user = User.find_by(username: bot_username)
      bot_user_id = bot_user.id

      mentions_bot_name = message_contents.downcase =~ /@#{bot_username.downcase}\b/

      prior_message = ::Chat::Message.where(chat_channel_id: channel_id).second_to_last
      replied_to_user = nil
      if in_reply_to_id
        ::DiscourseChatbot.progress_debug_message("2.5 found it's a reply to a prior message")
        replied_to_user = ::Chat::Message.find(in_reply_to_id).user
      end

      channel = ::Chat::Channel.find(channel_id)
      direct_message_channel = channel.chatable_type == DIRECT_MESSAGE
      direct_message_channel_user_count = nil
      if direct_message_channel
        # we don't need to calculate this unless it's direct message so keep within if statement to improve performance
        direct_message_channel_user_count = ::Chat::UserChatChannelMembership.where(chat_channel_id: channel_id).count
      end
      bot_chat_channel = (bot_user.user_chat_channel_memberships.where(chat_channel_id: channel_id).count > 0)

      talking_to_bot = (direct_message_channel && bot_chat_channel && direct_message_channel_user_count && direct_message_channel_user_count < 3) || (replied_to_user && replied_to_user.id == bot_user_id)

      if bot_user && (user_id != bot_user_id) && (mentions_bot_name || talking_to_bot)

        if mentions_bot_name && !bot_chat_channel
          bot_user.user_chat_channel_memberships.create!(chat_channel: channel, following: true)
          Jobs::Chat::UpdateChannelUserCount.new.execute(chat_channel_id: channel.id)
          channel.reload
          ::DiscourseChatbot.progress_debug_message("2.6 added bot to channel")
        end

        opts = {
            type: MESSAGE,
            user_id: user_id,
            bot_user_id: bot_user_id,
            reply_to_message_or_post_id: chat_message.id,
            topic_or_channel_id: channel_id,
            over_quota: over_quota,
            message_body: message_contents.gsub(bot_username.downcase, '').gsub(bot_username, '')
          }

        ::DiscourseChatbot.progress_debug_message("3. invocation")

        job_class = ::Jobs::ChatbotReplyJob
        invoke_background_job(job_class, opts)
        true
      else
        false
      end
    end

    private

    def invoke_background_job(job_class, opts)
      super(job_class, opts)
    end

  end
end
