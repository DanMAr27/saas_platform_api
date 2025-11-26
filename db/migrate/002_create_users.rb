# frozen_string_literal: true

# Migración para crear la tabla de usuarios
# Incluye todos los campos de Devise más campos personalizados
# Esta tabla es la identidad base de TODO el sistema (platform y tenant users)

class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      # ============================================
      # DEVISE: Database Authenticatable
      # ============================================
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      # ============================================
      # DEVISE: Recoverable
      # ============================================
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      # ============================================
      # DEVISE: Rememberable
      # ============================================
      t.datetime :remember_created_at

      # ============================================
      # DEVISE: Trackable
      # ============================================
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      # ============================================
      # DEVISE: Lockable
      # ============================================
      t.integer  :failed_attempts, default: 0, null: false
      t.string   :unlock_token
      t.datetime :locked_at

      # ============================================
      # CAMPOS PERSONALIZADOS
      # ============================================

      # Información personal
      t.string :first_name, limit: 100, null: false
      t.string :last_name, limit: 100, null: false
      t.string :phone, limit: 20
      t.string :avatar_url, limit: 500

      # Verificación de email
      t.datetime :email_verified_at

      # Sistema de invitaciones
      t.string :invitation_token, limit: 64
      t.datetime :invitation_expires_at
      t.datetime :invitation_accepted_at
      t.bigint :invited_by_id # FK a users.id

      # Último login (adicional a Devise trackable)
      t.datetime :last_login_at

      # ============================================
      # SOFT DELETE
      # ============================================
      t.datetime :deleted_at
      t.bigint :deleted_by # FK a users.id

      # ============================================
      # TIMESTAMPS
      # ============================================
      t.timestamps
    end

    # ============================================
    # ÍNDICES
    # ============================================

    # Email único (principal método de login)
    add_index :users, :email, unique: true, name: 'index_users_on_email'

    # Índices de Devise
    add_index :users, :reset_password_token, unique: true, name: 'index_users_on_reset_password_token'
    add_index :users, :unlock_token, unique: true, name: 'index_users_on_unlock_token'

    # Invitaciones
    add_index :users, :invitation_token, unique: true, name: 'index_users_on_invitation_token'
    add_index :users, :invited_by_id, name: 'index_users_on_invited_by_id'

    # Soft delete (para queries de usuarios activos)
    add_index :users, :deleted_at, name: 'index_users_on_deleted_at'

    # Búsquedas por nombre
    add_index :users, [ :first_name, :last_name ], name: 'index_users_on_first_name_and_last_name'

    # Email verificado (para filtrar usuarios verificados)
    add_index :users, :email_verified_at, name: 'index_users_on_email_verified_at'
  end
end
