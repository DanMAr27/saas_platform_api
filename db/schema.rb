# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 14) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "jwt_blacklists", force: :cascade do |t|
    t.string "jti", null: false
    t.bigint "user_id", null: false
    t.datetime "exp", null: false
    t.datetime "created_at", null: false
    t.index ["exp"], name: "index_jwt_blacklist_on_exp"
    t.index ["jti"], name: "index_jwt_blacklist_on_jti", unique: true
    t.index ["user_id"], name: "index_jwt_blacklist_on_user_id"
  end

  create_table "organizational_node_closures", force: :cascade do |t|
    t.bigint "ancestor_id", null: false
    t.bigint "descendant_id", null: false
    t.integer "depth", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ancestor_id", "descendant_id"], name: "index_org_node_closures_on_ancestor_and_descendant", unique: true
    t.index ["ancestor_id"], name: "index_organizational_node_closures_on_ancestor_id"
    t.index ["depth"], name: "index_organizational_node_closures_on_depth"
    t.index ["descendant_id"], name: "index_organizational_node_closures_on_descendant_id"
  end

  create_table "organizational_node_levels", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.text "description"
    t.integer "level_order", default: 1, null: false
    t.boolean "allows_vehicles", default: true, null: false
    t.boolean "allows_users", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "settings", default: {}
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_organizational_node_levels_on_deleted_at"
    t.index ["level_order"], name: "index_organizational_node_levels_on_level_order"
    t.index ["tenant_id", "slug"], name: "index_org_node_levels_on_tenant_and_slug", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_organizational_node_levels_on_tenant_id"
  end

  create_table "organizational_nodes", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "level_id", null: false
    t.bigint "parent_id"
    t.string "name", limit: 255, null: false
    t.string "code", limit: 50
    t.text "description"
    t.string "address", limit: 500
    t.string "city", limit: 100
    t.string "state", limit: 100
    t.string "postal_code", limit: 20
    t.string "country", limit: 2
    t.string "phone", limit: 20
    t.string "email", limit: 255
    t.string "status", limit: 20, default: "active", null: false
    t.jsonb "metadata", default: {}
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_organizational_nodes_on_deleted_at"
    t.index ["level_id"], name: "index_organizational_nodes_on_level_id"
    t.index ["parent_id"], name: "index_organizational_nodes_on_parent_id"
    t.index ["status"], name: "index_organizational_nodes_on_status"
    t.index ["tenant_id", "code"], name: "index_organizational_nodes_on_tenant_id_and_code", unique: true, where: "((code IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["tenant_id"], name: "index_organizational_nodes_on_tenant_id"
  end

  create_table "platform_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.string "context", limit: 20, default: "platform", null: false
    t.boolean "mfa_enabled", default: false, null: false
    t.datetime "mfa_configured_at"
    t.boolean "can_impersonate", default: false, null: false
    t.datetime "last_impersonation_at"
    t.jsonb "allowed_ips", default: []
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_platform_memberships_on_deleted_at"
    t.index ["mfa_enabled"], name: "index_platform_memberships_on_mfa_enabled"
    t.index ["role_id"], name: "index_platform_memberships_on_role_id"
    t.index ["user_id"], name: "index_platform_memberships_on_user_id", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.text "description"
    t.string "context", limit: 20, null: false
    t.boolean "requires_scope", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.integer "priority", default: 0, null: false
    t.boolean "allows_node_scope", default: false, null: false
    t.boolean "allows_vehicle_scope", default: false, null: false
    t.boolean "requires_any_scope", default: false, null: false
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["allows_node_scope"], name: "index_roles_on_allows_node_scope"
    t.index ["allows_vehicle_scope"], name: "index_roles_on_allows_vehicle_scope"
    t.index ["context", "allows_node_scope"], name: "index_roles_on_context_and_node_scope"
    t.index ["context", "allows_vehicle_scope"], name: "index_roles_on_context_and_vehicle_scope"
    t.index ["context"], name: "index_roles_on_context"
    t.index ["is_system"], name: "index_roles_on_is_system"
    t.index ["priority"], name: "index_roles_on_priority"
    t.index ["requires_any_scope"], name: "index_roles_on_requires_any_scope"
    t.index ["settings"], name: "index_roles_on_settings", using: :gin
    t.index ["slug"], name: "index_roles_on_slug", unique: true
  end

  create_table "tenant_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "tenant_id", null: false
    t.bigint "role_id", null: false
    t.boolean "is_primary_admin", default: false, null: false
    t.string "status", limit: 20, default: "invited", null: false
    t.string "invitation_token", limit: 64
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.boolean "is_default", default: false, null: false
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_tenant_memberships_on_deleted_at"
    t.index ["invitation_token"], name: "index_tenant_memberships_on_invitation_token", unique: true, where: "(invitation_token IS NOT NULL)"
    t.index ["role_id"], name: "index_tenant_memberships_on_role_id"
    t.index ["status"], name: "index_tenant_memberships_on_status"
    t.index ["tenant_id", "is_primary_admin"], name: "index_tenant_memberships_on_tenant_primary_admin", unique: true, where: "((is_primary_admin = true) AND (deleted_at IS NULL))"
    t.index ["tenant_id"], name: "index_tenant_memberships_on_tenant_id"
    t.index ["user_id", "tenant_id", "role_id"], name: "index_tenant_memberships_on_user_tenant_role", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_tenant_memberships_on_user_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 100, null: false
    t.string "domain", limit: 255
    t.string "legal_name", limit: 255
    t.string "tax_id", limit: 50
    t.text "address"
    t.string "city", limit: 100
    t.string "state", limit: 100
    t.string "postal_code", limit: 20
    t.string "country", limit: 2, default: "ES"
    t.string "timezone", limit: 50, default: "Europe/Madrid"
    t.string "locale", limit: 10, default: "es"
    t.string "currency", limit: 3, default: "EUR"
    t.string "status", limit: 20, default: "trial", null: false
    t.date "trial_ends_at"
    t.date "subscription_starts_at"
    t.date "subscription_ends_at"
    t.string "plan", limit: 50, default: "trial"
    t.integer "max_users", default: 5
    t.integer "max_storage_gb", default: 10
    t.jsonb "settings", default: {}
    t.jsonb "metadata", default: {}
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by"], name: "index_tenants_on_created_by"
    t.index ["deleted_at"], name: "index_tenants_on_deleted_at"
    t.index ["domain"], name: "index_tenants_on_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["metadata"], name: "index_tenants_on_metadata", using: :gin
    t.index ["name"], name: "index_tenants_on_name"
    t.index ["settings"], name: "index_tenants_on_settings", using: :gin
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
    t.index ["status"], name: "index_tenants_on_status"
  end

  create_table "user_node_scopes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organizational_node_id", null: false
    t.bigint "tenant_id", null: false
    t.bigint "role_id"
    t.string "access_type", limit: 20, default: "read", null: false
    t.boolean "include_children", default: true, null: false
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_user_node_scopes_on_deleted_at"
    t.index ["organizational_node_id"], name: "index_user_node_scopes_on_organizational_node_id"
    t.index ["role_id"], name: "index_user_node_scopes_on_role_id"
    t.index ["tenant_id"], name: "index_user_node_scopes_on_tenant_id"
    t.index ["user_id", "organizational_node_id", "tenant_id", "role_id"], name: "index_user_node_scopes_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_user_node_scopes_on_user_id"
  end

  create_table "user_vehicle_scopes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "vehicle_id", null: false
    t.bigint "tenant_id", null: false
    t.bigint "role_id"
    t.string "access_type", limit: 20, default: "read", null: false
    t.datetime "valid_from"
    t.datetime "valid_until"
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_user_vehicle_scopes_on_deleted_at"
    t.index ["role_id"], name: "index_user_vehicle_scopes_on_role_id"
    t.index ["tenant_id"], name: "index_user_vehicle_scopes_on_tenant_id"
    t.index ["user_id", "vehicle_id", "tenant_id", "role_id"], name: "index_user_vehicle_scopes_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["user_id"], name: "index_user_vehicle_scopes_on_user_id"
    t.index ["valid_from"], name: "index_user_vehicle_scopes_on_valid_from"
    t.index ["valid_until"], name: "index_user_vehicle_scopes_on_valid_until"
    t.index ["vehicle_id"], name: "index_user_vehicle_scopes_on_vehicle_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.string "first_name", limit: 100, null: false
    t.string "last_name", limit: 100, null: false
    t.string "phone", limit: 20
    t.string "avatar_url", limit: 500
    t.datetime "email_verified_at"
    t.string "invitation_token", limit: 64
    t.datetime "invitation_expires_at"
    t.datetime "invitation_accepted_at"
    t.bigint "invited_by_id"
    t.datetime "last_login_at"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verified_at"], name: "index_users_on_email_verified_at"
    t.index ["first_name", "last_name"], name: "index_users_on_first_name_and_last_name"
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "vehicles", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "organizational_node_id"
    t.string "name", limit: 255, null: false
    t.string "license_plate", limit: 20, null: false
    t.string "vin", limit: 50
    t.string "fleet_number", limit: 50
    t.string "vehicle_type", limit: 50
    t.string "make", limit: 100
    t.string "model", limit: 100
    t.integer "year"
    t.string "status", limit: 20, default: "active", null: false
    t.date "purchase_date"
    t.date "registration_expires_at"
    t.date "insurance_expires_at"
    t.date "last_maintenance_date"
    t.integer "odometer"
    t.string "color", limit: 50
    t.string "fuel_type", limit: 20
    t.decimal "fuel_capacity", precision: 10, scale: 2
    t.integer "passenger_capacity"
    t.jsonb "metadata", default: {}
    t.jsonb "specifications", default: {}
    t.bigint "created_by"
    t.datetime "deleted_at"
    t.bigint "deleted_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_vehicles_on_deleted_at"
    t.index ["organizational_node_id"], name: "index_vehicles_on_organizational_node_id"
    t.index ["status"], name: "index_vehicles_on_status"
    t.index ["tenant_id", "fleet_number"], name: "index_vehicles_on_tenant_id_and_fleet_number", unique: true, where: "((fleet_number IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["tenant_id", "license_plate"], name: "index_vehicles_on_tenant_id_and_license_plate", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_vehicles_on_tenant_id"
    t.index ["vehicle_type"], name: "index_vehicles_on_vehicle_type"
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.jsonb "object"
    t.jsonb "object_changes"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.index "((metadata ->> 'tenant_id'::text))", name: "index_versions_on_tenant_id"
    t.index ["created_at"], name: "index_versions_on_created_at"
    t.index ["event"], name: "index_versions_on_event"
    t.index ["item_id"], name: "index_versions_on_item_id"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["item_type"], name: "index_versions_on_item_type"
    t.index ["metadata"], name: "index_versions_on_metadata", using: :gin
    t.index ["whodunnit"], name: "index_versions_on_whodunnit"
  end

  add_foreign_key "jwt_blacklists", "users", on_delete: :cascade
  add_foreign_key "organizational_node_closures", "organizational_nodes", column: "ancestor_id", on_delete: :cascade
  add_foreign_key "organizational_node_closures", "organizational_nodes", column: "descendant_id", on_delete: :cascade
  add_foreign_key "organizational_node_levels", "tenants", on_delete: :cascade
  add_foreign_key "organizational_node_levels", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "organizational_nodes", "organizational_node_levels", column: "level_id", on_delete: :restrict
  add_foreign_key "organizational_nodes", "organizational_nodes", column: "parent_id", on_delete: :restrict
  add_foreign_key "organizational_nodes", "tenants", on_delete: :cascade
  add_foreign_key "organizational_nodes", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "platform_memberships", "roles", on_delete: :restrict
  add_foreign_key "platform_memberships", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "platform_memberships", "users", on_delete: :cascade
  add_foreign_key "tenant_memberships", "roles", on_delete: :restrict
  add_foreign_key "tenant_memberships", "tenants", on_delete: :cascade
  add_foreign_key "tenant_memberships", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "tenant_memberships", "users", on_delete: :cascade
  add_foreign_key "tenants", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "user_node_scopes", "organizational_nodes", on_delete: :cascade
  add_foreign_key "user_node_scopes", "roles", on_delete: :nullify
  add_foreign_key "user_node_scopes", "tenants", on_delete: :cascade
  add_foreign_key "user_node_scopes", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "user_node_scopes", "users", on_delete: :cascade
  add_foreign_key "user_vehicle_scopes", "roles", on_delete: :nullify
  add_foreign_key "user_vehicle_scopes", "tenants", on_delete: :cascade
  add_foreign_key "user_vehicle_scopes", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "user_vehicle_scopes", "users", on_delete: :cascade
  add_foreign_key "user_vehicle_scopes", "vehicles", on_delete: :cascade
  add_foreign_key "vehicles", "organizational_nodes", on_delete: :nullify
  add_foreign_key "vehicles", "tenants", on_delete: :cascade
  add_foreign_key "vehicles", "users", column: "created_by", on_delete: :nullify
end
