# frozen_string_literal: true

# db/seeds/01_roles.rb
# Catálogo completo de roles del sistema

puts "\n🎭 Creating Roles..."

# ============================================
# ROLES DE PLATAFORMA
# ============================================

puts "\n  Platform Roles:"

super_admin_role = Role.create_with(
  name: 'Super Admin',
  description: 'Full access to the entire platform. Can manage all tenants, users, and system settings. Has unrestricted access to all data and features.',
  context: 'platform',
  is_system: true,
  priority: 1,
  requires_scope: false,
  settings: {
    can_access_all_tenants: true,
    can_manage_platform_settings: true,
    can_manage_all_users: true,
    can_delete_tenants: true,
    can_view_audit_logs: true
  }
).find_or_create_by!(slug: 'super_admin')
puts "    ✓ Super Admin"

support_admin_role = Role.create_with(
  name: 'Support Admin',
  description: 'Customer support access. Can view and impersonate users across tenants for troubleshooting. Read-only access to most data.',
  context: 'platform',
  is_system: true,
  priority: 2,
  requires_scope: false,
  settings: {
    can_impersonate_users: true,
    can_view_all_tenants: true,
    can_access_support_tools: true,
    can_view_audit_logs: true,
    requires_mfa: true
  }
).find_or_create_by!(slug: 'support_admin')
puts "    ✓ Support Admin"

# ============================================
# ROLES DE TENANT
# ============================================

puts "\n  Tenant Roles:"

tenant_admin_role = Role.create_with(
  name: 'Tenant Admin',
  description: 'Full administrative access within the tenant. Can manage users, settings, billing, and all resources. Primary administrator role for tenant organizations.',
  context: 'tenant',
  is_system: true,
  priority: 10,
  requires_scope: false,
  settings: {
    can_manage_users: true,
    can_manage_billing: true,
    can_manage_settings: true,
    can_delete_resources: true,
    can_view_all_data: true,
    can_export_data: true
  }
).find_or_create_by!(slug: 'tenant_admin')
puts "    ✓ Tenant Admin"

tenant_manager_role = Role.create_with(
  name: 'Tenant Manager',
  description: 'Management access within assigned scope. Can view and edit resources, manage operations, but cannot manage users or billing. Ideal for department heads.',
  context: 'tenant',
  is_system: true,
  priority: 20,
  requires_scope: true,
  settings: {
    can_manage_resources: true,
    can_view_reports: true,
    can_create_records: true,
    can_edit_records: true,
    scope_types: [ 'organizational_node', 'vehicle' ]
  }
).find_or_create_by!(slug: 'tenant_manager')
puts "    ✓ Tenant Manager"

tenant_driver_role = Role.create_with(
  name: 'Tenant Driver',
  description: 'Basic operational access. Can view and use assigned resources. Limited editing permissions. Ideal for field workers and operational staff.',
  context: 'tenant',
  is_system: true,
  priority: 30,
  requires_scope: true,
  settings: {
    can_view_assigned_resources: true,
    can_update_status: true,
    can_add_notes: true,
    scope_types: [ 'vehicle' ],
    read_only_mode: false
  }
).find_or_create_by!(slug: 'tenant_driver')
puts "    ✓ Tenant Driver"

# ============================================
# ROLES ADICIONALES (OPCIONALES)
# ============================================

puts "\n  Additional Roles:"

tenant_viewer_role = Role.create_with(
  name: 'Tenant Viewer',
  description: 'Read-only access to tenant data. Can view reports and dashboards but cannot make changes. Ideal for stakeholders and auditors.',
  context: 'tenant',
  is_system: false,
  priority: 40,
  requires_scope: true,
  settings: {
    read_only: true,
    can_view_reports: true,
    can_export_reports: true,
    scope_types: [ 'organizational_node' ]
  }
).find_or_create_by!(slug: 'tenant_viewer')
puts "    ✓ Tenant Viewer"

fleet_coordinator_role = Role.create_with(
  name: 'Fleet Coordinator',
  description: 'Specialized role for vehicle fleet management. Can manage vehicles, maintenance schedules, and assignments.',
  context: 'tenant',
  is_system: false,
  priority: 25,
  requires_scope: true,
  settings: {
    can_manage_vehicles: true,
    can_schedule_maintenance: true,
    can_assign_drivers: true,
    scope_types: [ 'organizational_node', 'vehicle' ]
  }
).find_or_create_by!(slug: 'fleet_coordinator')
puts "    ✓ Fleet Coordinator"

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Roles Summary:"
puts "    - Total Roles: #{Role.count}"
puts "    - Platform Roles: #{Role.platform_roles.count}"
puts "    - Tenant Roles: #{Role.tenant_roles.count}"
puts "    - System Roles: #{Role.system_roles.count}"
puts "    - Custom Roles: #{Role.custom_roles.count}"

puts "\n  📋 Role Details:"
Role.by_priority.each do |role|
  scope_text = role.requires_scope? ? " (requires scope)" : ""
  system_text = role.is_system? ? " [SYSTEM]" : ""
  puts "    #{role.priority}. #{role.name} (#{role.context})#{scope_text}#{system_text}"
end
