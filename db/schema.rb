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

ActiveRecord::Schema[8.0].define(version: 8) do
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
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["context"], name: "index_roles_on_context"
    t.index ["is_system"], name: "index_roles_on_is_system"
    t.index ["priority"], name: "index_roles_on_priority"
    t.index ["settings"], name: "index_roles_on_settings", using: :gin
    t.index ["slug"], name: "index_roles_on_slug", unique: true
  end

  create_table "tenant_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "tenant_id", null: false
    t.string "role", limit: 50, default: "driver", null: false
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
    t.bigint "role_id"
    t.index ["deleted_at"], name: "index_tenant_memberships_on_deleted_at"
    t.index ["invitation_token"], name: "index_tenant_memberships_on_invitation_token", unique: true, where: "(invitation_token IS NOT NULL)"
    t.index ["role_id"], name: "index_tenant_memberships_on_role_id"
    t.index ["status"], name: "index_tenant_memberships_on_status"
    t.index ["tenant_id", "is_primary_admin"], name: "index_tenant_memberships_on_tenant_primary_admin", unique: true, where: "((is_primary_admin = true) AND (deleted_at IS NULL))"
    t.index ["tenant_id"], name: "index_tenant_memberships_on_tenant_id"
    t.index ["user_id", "tenant_id", "role"], name: "index_tenant_memberships_on_user_tenant_role", unique: true, where: "(deleted_at IS NULL)"
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
  add_foreign_key "platform_memberships", "roles", on_delete: :restrict
  add_foreign_key "platform_memberships", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "platform_memberships", "users", on_delete: :cascade
  add_foreign_key "tenant_memberships", "roles", on_delete: :restrict
  add_foreign_key "tenant_memberships", "tenants", on_delete: :cascade
  add_foreign_key "tenant_memberships", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "tenant_memberships", "users", on_delete: :cascade
  add_foreign_key "tenants", "users", column: "created_by", on_delete: :nullify
end
