class CreatePlatformMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_memberships do |t|
      # ============================================
      # RELACIONES
      # ============================================
      t.bigint :user_id, null: false
      t.bigint :role_id, null: false

      # ============================================
      # CONFIGURACIÓN
      # ============================================

      # Contexto (siempre 'platform' para esta tabla)
      t.string :context, null: false, default: 'platform', limit: 20

      # MFA obligatorio para acceso de plataforma
      t.boolean :mfa_enabled, default: false, null: false
      t.datetime :mfa_configured_at

      # Capacidad de impersonar usuarios (solo SupportAdmin)
      t.boolean :can_impersonate, default: false, null: false

      # Última vez que impersonó a alguien
      t.datetime :last_impersonation_at

      # IP permitidas (opcional, para mayor seguridad)
      t.jsonb :allowed_ips, default: []

      # ============================================
      # AUDITORÍA
      # ============================================
      t.bigint :created_by # FK a users.id
      t.datetime :deleted_at
      t.bigint :deleted_by

      # ============================================
      # TIMESTAMPS
      # ============================================
      t.timestamps
    end

    # ============================================
    # ÍNDICES
    # ============================================

    # Un usuario solo puede tener una platform membership
    add_index :platform_memberships,
              :user_id,
              unique: true,
              name: 'index_platform_memberships_on_user_id',
              where: 'deleted_at IS NULL'

    # Búsqueda por rol
    add_index :platform_memberships, :role_id, name: 'index_platform_memberships_on_role_id'

    # Soft delete
    add_index :platform_memberships, :deleted_at, name: 'index_platform_memberships_on_deleted_at'

    # MFA habilitado
    add_index :platform_memberships, :mfa_enabled, name: 'index_platform_memberships_on_mfa_enabled'

    # ============================================
    # FOREIGN KEYS
    # ============================================
    add_foreign_key :platform_memberships, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :platform_memberships, :roles, column: :role_id, on_delete: :restrict
    add_foreign_key :platform_memberships, :users, column: :created_by, on_delete: :nullify
  end
end
