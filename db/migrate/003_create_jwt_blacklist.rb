# frozen_string_literal: true

# Migración para la lista negra de tokens JWT (revocación)
# Cuando un usuario hace logout, su token se agrega aquí para invalidarlo

class CreateJwtBlacklist < ActiveRecord::Migration[8.0]
  def change
    create_table :jwt_blacklists do |t|
      # JTI (JWT ID) - Identificador único del token
      t.string :jti, null: false

      # Usuario al que pertenece el token
      t.bigint :user_id, null: false

      # Cuándo expira el token (para limpieza automática)
      t.datetime :exp, null: false

      # Timestamp de creación
      t.datetime :created_at, null: false
    end

    # Índices
    add_index :jwt_blacklists, :jti, unique: true, name: 'index_jwt_blacklist_on_jti'
    add_index :jwt_blacklists, :user_id, name: 'index_jwt_blacklist_on_user_id'
    add_index :jwt_blacklists, :exp, name: 'index_jwt_blacklist_on_exp'

    # FK a users
    add_foreign_key :jwt_blacklists, :users, column: :user_id, on_delete: :cascade
  end
end
