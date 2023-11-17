# frozen_string_literal: true

class DropLegacyChatbotEmbeddingsIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :chatbot_post_embeddings, column: [:embedding], name: 'hnsw_index_on_chatbot_post_embeddings', if_exists: true
  end
end
