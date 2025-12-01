class CreateTenantMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :tenant_memberships do |t|
      # ============================================
      # RELACIONES
      # ============================================
      t.bigint :user_id, null: false
      t.bigint :tenant_id, null: false

      # Rol del usuario en este tenant (por ahora como string, en Fase 3 será FK)
      # Roles: 'admin', 'manager', 'driver'
      t.bigint :role_id, null: false

      # ============================================
      # METADATA DE LA MEMBRESÍA
      # ============================================

      # ¿Es el admin principal del tenant? (solo puede haber uno)
      t.boolean :is_primary_admin, default: false, null: false

      # Estado de la membresía: active, suspended, invited
      t.string :status, limit: 20, null: false, default: 'invited'

      # Token de invitación (si aplica)
      t.string :invitation_token, limit: 64
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at

      # ¿Es el tenant por defecto para este usuario?
      t.boolean :is_default, default: false, null: false

      # ============================================
      # AUDITORÍA
      # ============================================
      t.bigint :created_by # FK a users.id - quien creó la membresía
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

    # Índice para role_id (de la segunda migración)
    add_index :tenant_memberships, :role_id, name: 'index_tenant_memberships_on_role_id'

    # Combinación única: un usuario no puede tener el mismo rol dos veces en un tenant
    # *** CAMBIO AQUÍ: Ahora usa role_id en lugar de role (string) ***
    add_index :tenant_memberships,
              [ :user_id, :tenant_id, :role_id ], # <-- Usamos role_id
              unique: true,
              name: 'index_tenant_memberships_on_user_tenant_role',
              where: 'deleted_at IS NULL'

    # Buscar membresías por usuario
    add_index :tenant_memberships, :user_id, name: 'index_tenant_memberships_on_user_id'

    # Buscar membresías por tenant
    add_index :tenant_memberships, :tenant_id, name: 'index_tenant_memberships_on_tenant_id'

    # Solo puede haber un primary admin por tenant
    add_index :tenant_memberships,
              [ :tenant_id, :is_primary_admin ],
              unique: true,
              name: 'index_tenant_memberships_on_tenant_primary_admin',
              where: 'is_primary_admin = true AND deleted_at IS NULL'

    # Buscar por estado
    add_index :tenant_memberships, :status, name: 'index_tenant_memberships_on_status'

    # Soft delete
    add_index :tenant_memberships, :deleted_at, name: 'index_tenant_memberships_on_deleted_at'

    # Token de invitación
    add_index :tenant_memberships,
              :invitation_token,
              unique: true,
              name: 'index_tenant_memberships_on_invitation_token',
              where: 'invitation_token IS NOT NULL'

    # ============================================
    # FOREIGN KEYS
    # ============================================
    add_foreign_key :tenant_memberships, :roles, column: :role_id, on_delete: :restrict
    add_foreign_key :tenant_memberships, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :tenant_memberships, :tenants, column: :tenant_id, on_delete: :cascade
    add_foreign_key :tenant_memberships, :users, column: :created_by, on_delete: :nullify
  end
end
