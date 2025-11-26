# frozen_string_literal: true

# Migración para crear la tabla de Tenants (organizaciones/clientes)
# Cada tenant es un espacio aislado con sus propios datos

class CreateTenants < ActiveRecord::Migration[8.0]
  def change
    create_table :tenants do |t|
      # ============================================
      # IDENTIFICACIÓN
      # ============================================
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 100
      t.string :domain, limit: 255

      # ============================================
      # INFORMACIÓN LEGAL
      # ============================================
      t.string :legal_name, limit: 255
      t.string :tax_id, limit: 50
      t.text :address
      t.string :city, limit: 100
      t.string :state, limit: 100
      t.string :postal_code, limit: 20
      t.string :country, limit: 2, default: 'ES' # ISO 3166-1 alpha-2

      # ============================================
      # CONFIGURACIÓN
      # ============================================
      t.string :timezone, limit: 50, default: 'Europe/Madrid'
      t.string :locale, limit: 10, default: 'es'
      t.string :currency, limit: 3, default: 'EUR' # ISO 4217

      # ============================================
      # ESTADO Y BILLING
      # ============================================
      # Estados: active, suspended, trial, cancelled
      t.string :status, limit: 20, null: false, default: 'trial'
      t.date :trial_ends_at
      t.date :subscription_starts_at
      t.date :subscription_ends_at

      # Plan/tier (basic, professional, enterprise)
      t.string :plan, limit: 50, default: 'trial'

      # Límites según el plan
      t.integer :max_users, default: 5
      t.integer :max_storage_gb, default: 10

      # ============================================
      # METADATA Y CONFIGURACIÓN
      # ============================================
      t.jsonb :settings, default: {}
      t.jsonb :metadata, default: {}

      # ============================================
      # AUDITORÍA
      # ============================================
      t.bigint :created_by # FK a users.id
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

    # Slug único (para URLs amigables)
    add_index :tenants, :slug, unique: true, name: 'index_tenants_on_slug'

    # Dominio único si se usa
    add_index :tenants, :domain, unique: true, name: 'index_tenants_on_domain', where: 'domain IS NOT NULL'

    # Estado (para filtrar por activos/suspendidos)
    add_index :tenants, :status, name: 'index_tenants_on_status'

    # Soft delete
    add_index :tenants, :deleted_at, name: 'index_tenants_on_deleted_at'

    # Búsqueda por nombre
    add_index :tenants, :name, name: 'index_tenants_on_name'

    # Índice GIN para búsquedas en JSONB
    add_index :tenants, :settings, using: :gin, name: 'index_tenants_on_settings'
    add_index :tenants, :metadata, using: :gin, name: 'index_tenants_on_metadata'

    # Creador
    add_index :tenants, :created_by, name: 'index_tenants_on_created_by'

    # ============================================
    # FOREIGN KEYS
    # ============================================
    add_foreign_key :tenants, :users, column: :created_by, on_delete: :nullify
  end
end
