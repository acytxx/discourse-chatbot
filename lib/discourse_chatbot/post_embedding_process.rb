# frozen_string_literal: true
require "openai"

module ::DiscourseChatbot

  class PostEmbeddingProcess

    def initialize
      ::OpenAI.configure do |config|
        config.access_token = SiteSetting.chatbot_open_ai_token
      end
      if !SiteSetting.chatbot_open_ai_model_custom_url.blank?
        ::OpenAI.configure do |config|
          config.uri_base = SiteSetting.chatbot_open_ai_model_custom_url
        end
      end
      if SiteSetting.chatbot_open_ai_model_custom_api_type == "azure"
        ::OpenAI.configure do |config|
          config.api_type = :azure
          config.api_version = SiteSetting.chatbot_open_ai_model_custom_api_version
        end
      end
      @model_name = ::DiscourseChatbot::EMBEDDING_MODEL
      @client = ::OpenAI::Client.new

      allowed_group_ids = [0, 10, 11, 12, 13, 14]  # automated groups only
      barred_group_ids = Group.where.not(id: allowed_group_ids).pluck(:id) # no custom groups
      unsuitable_users = GroupUser.where(group_id: barred_group_ids).pluck(:user_id).uniq # don't choose someone with in a custom group
      safe_users = User.where.not(id: unsuitable_users).distinct.pluck(:id) # exclude them and find a suitable vanilla, junior user
      benchmark_user = User.where(id: safe_users).where(trust_level: SiteSetting.chatbot_embeddings_benchmark_user_trust_level, active: true, admin: false, suspended_at: nil).last
      if benchmark_user.nil?
        raise StandardError, "No benchmark user exists for Post embedding suitability check, please add a basic user"
      end
      @benchmark_user_guardian = Guardian.new(benchmark_user)
    end

    def upsert(post_id)
      post = ::Post.find_by(id: post_id)
      topic = ::Topic.find_by(id: post.topic_id)

      return if post.nil? || topic.nil?
      return if topic.archetype == Archetype.private_message
      return if @benchmark_user_guardian.nil?

      if @benchmark_user_guardian.can_see?(post)
        response = @client.embeddings(
          parameters: {
            model: @model_name,
            input: post.raw[0..::DiscourseChatbot::EMBEDDING_CHAR_LIMIT]
          }
        )

        embedding_vector = response.dig("data", 0, "embedding")

        ::DiscourseChatbot::PostEmbedding.upsert({ post_id: post_id, embedding: "#{embedding_vector}" }, on_duplicate: :update, unique_by: :post_id)
      end
    end

    def semantic_search(query)
      response = @client.embeddings(
        parameters: {
          model: @model_name,
          input: query[0..::DiscourseChatbot::EMBEDDING_CHAR_LIMIT]
        }
       )

       query_vector = response.dig("data", 0, "embedding")

       begin
         search_result_post_ids =
           DB.query(<<~SQL, query_embedding: query_vector, limit: 10).map(
              SELECT
                post_id
              FROM
                chatbot_post_embeddings
              ORDER BY
               embedding <-> '[:query_embedding]'
              LIMIT :limit
            SQL
             &:post_id
           )
        rescue PG::Error => e
          Rails.logger.error(
            "Error #{e} querying embeddings for search #{query}",
          )
         raise MissingEmbeddingError
       end
       search_result_post_ids
    end
  end
end
