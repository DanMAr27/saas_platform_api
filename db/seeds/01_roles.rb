# db/seeds/01_roles.rb
# Catálogo completo de roles del sistema
# ACTUALIZADO: Con nuevos campos de scope (allows_node_scope, allows_vehicle_scope, requires_any_scope)

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
  # 🆕 NUEVOS CAMPOS: Platform roles no usan scopes
  allows_node_scope: false,
  allows_vehicle_scope: false,
  requires_any_scope: false,
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
  # 🆕 NUEVOS CAMPOS: Platform roles no usan scopes
  allows_node_scope: false,
  allows_vehicle_scope: false,
  requires_any_scope: false,
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
# ROLES DE TENANT (SISTEMA)
# ============================================

puts "\n  Tenant Roles:"

tenant_admin_role = Role.create_with(
  name: 'Tenant Admin',
  description: 'Full administrative access within the tenant. Can manage users, settings, billing, and all resources. Primary administrator role for tenant organizations.',
  context: 'tenant',
  is_system: true,
  priority: 10,
  # 🆕 NUEVOS CAMPOS: Admin no requiere scopes = acceso total
  allows_node_scope: false,
  allows_vehicle_scope: false,
  requires_any_scope: false,
  settings: {
    can_manage_users: true,
    can_manage_billing: true,
    can_manage_settings: true,
    can_delete_resources: true,
    can_view_all_data: true,
    can_export_data: true,
    access_level: 'full'
  }
).find_or_create_by!(slug: 'tenant_admin')
puts "    ✓ Tenant Admin (no scopes required - full access)"

tenant_manager_role = Role.create_with(
  name: 'Tenant Manager',
  description: 'Management access within assigned organizational nodes. Can view and manage resources, operations, and users within their scope. Ideal for department heads and regional managers.',
  context: 'tenant',
  is_system: true,
  priority: 20,
  # 🆕 NUEVOS CAMPOS: Manager requiere NODE scopes
  allows_node_scope: true,      # ✅ Permite node scopes
  allows_vehicle_scope: false,  # ❌ No permite vehicle scopes
  requires_any_scope: true,     # ✅ Requiere al menos un scope
  settings: {
    can_manage_resources: true,
    can_view_reports: true,
    can_create_records: true,
    can_edit_records: true,
    can_view_all_vehicles: true,      # Puede ver todos los vehículos
    can_manage_node_vehicles: true,   # Puede gestionar vehículos en sus nodos
    can_manage_node_users: true,      # Puede gestionar usuarios en sus nodos
    access_level: 'node_based'
  }
).find_or_create_by!(slug: 'tenant_manager')
puts "    ✓ Tenant Manager (requires node scopes)"

tenant_driver_role = Role.create_with(
  name: 'Tenant Driver',
  description: 'Basic operational access to assigned vehicles. Can operate vehicles, create trips, and view basic reports. Limited to assigned vehicle scope only.',
  context: 'tenant',
  is_system: true,
  priority: 30,
  # 🆕 NUEVOS CAMPOS: Driver requiere VEHICLE scopes
  allows_node_scope: false,     # ❌ No permite node scopes
  allows_vehicle_scope: true,   # ✅ Permite vehicle scopes
  requires_any_scope: true,     # ✅ Requiere al menos un scope
  settings: {
    can_view_assigned_resources: true,
    can_update_status: true,
    can_add_notes: true,
    can_drive_vehicles: true,
    can_create_trips: true,
    can_view_own_reports: true,
    access_level: 'vehicle_based'
  }
).find_or_create_by!(slug: 'tenant_driver')
puts "    ✓ Tenant Driver (requires vehicle scopes)"

# ============================================
# ROLES ADICIONALES (OPCIONALES/CUSTOM)
# ============================================

puts "\n  Additional Custom Roles:"

tenant_viewer_role = Role.create_with(
  name: 'Tenant Viewer',
  description: 'Read-only access to assigned organizational nodes. Can view reports and dashboards but cannot make changes. Ideal for stakeholders and auditors.',
  context: 'tenant',
  is_system: false,
  priority: 40,
  # 🆕 NUEVOS CAMPOS: Viewer requiere NODE scopes (solo lectura)
  allows_node_scope: true,
  allows_vehicle_scope: false,
  requires_any_scope: true,
  settings: {
    read_only: true,
    can_view_reports: true,
    can_export_reports: true,
    can_view_dashboards: true,
    access_level: 'node_based_readonly'
  }
).find_or_create_by!(slug: 'tenant_viewer')
puts "    ✓ Tenant Viewer (requires node scopes - read only)"

fleet_coordinator_role = Role.create_with(
  name: 'Fleet Coordinator',
  description: 'Specialized role for vehicle fleet management within assigned nodes. Can manage vehicles, maintenance schedules, and driver assignments.',
  context: 'tenant',
  is_system: false,
  priority: 25,
  # 🆕 NUEVOS CAMPOS: Fleet Coordinator requiere NODE scopes
  # (gestiona vehículos dentro de nodos, no vehículos individuales)
  allows_node_scope: true,
  allows_vehicle_scope: false,
  requires_any_scope: true,
  settings: {
    can_manage_vehicles: true,
    can_schedule_maintenance: true,
    can_assign_drivers: true,
    can_view_vehicle_reports: true,
    can_manage_fleet_assignments: true,
    access_level: 'node_based'
  }
).find_or_create_by!(slug: 'fleet_coordinator')
puts "    ✓ Fleet Coordinator (requires node scopes)"

# 🆕 NUEVO ROL OPCIONAL: Operador (multi-scope teórico, comentado por ahora)
# Descomentar si en el futuro se necesita un rol que maneje AMBOS tipos de scope
# (requeriría cambiar la validación de exclusividad en Scopeable)
=begin
operator_role = Role.create_with(
  name: 'Tenant Operator',
  description: 'Hybrid operational role with access to both nodes and vehicles.',
  context: 'tenant',
  is_system: false,
  priority: 35,
  allows_node_scope: true,
  allows_vehicle_scope: true,
  requires_any_scope: true,
  settings: {
    can_operate_vehicles: true,
    can_manage_node_operations: true,
    access_level: 'hybrid'
  }
).find_or_create_by!(slug: 'tenant_operator')
puts "    ✓ Tenant Operator (requires node OR vehicle scopes)"
=end

# ============================================
# ACTUALIZAR ROLES EXISTENTES (Si ya existen)
# ============================================

puts "\n  Updating existing roles with scope flags..."

# Actualizar roles existentes que no tienen los nuevos campos
Role.where(allows_node_scope: nil).find_each do |role|
  case role.slug
  when 'super_admin', 'support_admin', 'tenant_admin'
    role.update!(
      allows_node_scope: false,
      allows_vehicle_scope: false,
      requires_any_scope: false
    )
  when 'tenant_manager', 'tenant_viewer', 'fleet_coordinator'
    role.update!(
      allows_node_scope: true,
      allows_vehicle_scope: false,
      requires_any_scope: true
    )
  when 'tenant_driver'
    role.update!(
      allows_node_scope: false,
      allows_vehicle_scope: true,
      requires_any_scope: true
    )
  else
    # Roles custom sin configuración: por defecto sin scopes
    puts "    ⚠️  Custom role '#{role.name}' needs manual scope configuration"
  end
end

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Roles Summary:"
puts "    - Total Roles: #{Role.count}"
puts "    - Platform Roles: #{Role.platform_roles.count}"
puts "    - Tenant Roles: #{Role.tenant_roles.count}"
puts "    - System Roles: #{Role.system_roles.count}"
puts "    - Custom Roles: #{Role.custom_roles.count}"

puts "\n  🎯 Scope Distribution:"
puts "    - Roles requiring scopes: #{Role.with_scope_requirements.count}"
puts "    - Roles without scopes: #{Role.without_scope_requirements.count}"
puts "    - Node scope roles: #{Role.requiring_node_scopes.count}"
puts "    - Vehicle scope roles: #{Role.requiring_vehicle_scopes.count}"

puts "\n  📋 Role Details:"
Role.by_priority.each do |role|
  scope_info = if role.requires_any_scope?
    scope_type = role.allows_node_scope? ? "node" : "vehicle"
    " [requires #{scope_type} scope]"
  else
    " [no scopes - full access]"
  end

  system_text = role.is_system? ? " (SYSTEM)" : " (CUSTOM)"

  puts "    #{role.priority}. #{role.name} (#{role.context})#{scope_info}#{system_text}"
end

# ============================================
# VALIDACIÓN FINAL
# ============================================

puts "\n  ✅ Validation:"

# Verificar que todos los roles tienen los campos de scope configurados
invalid_roles = Role.where(allows_node_scope: nil)
                   .or(Role.where(allows_vehicle_scope: nil))
                   .or(Role.where(requires_any_scope: nil))

if invalid_roles.any?
  puts "    ⚠️  WARNING: #{invalid_roles.count} roles with missing scope configuration:"
  invalid_roles.each do |role|
    puts "       - #{role.name} (#{role.slug})"
  end
else
  puts "    ✓ All roles have valid scope configuration"
end

# Verificar que roles que requieren scopes tienen al menos un allow
invalid_requirements = Role.where(requires_any_scope: true)
                          .where(allows_node_scope: false, allows_vehicle_scope: false)

if invalid_requirements.any?
  puts "    ❌ ERROR: #{invalid_requirements.count} roles require scopes but don't allow any type:"
  invalid_requirements.each do |role|
    puts "       - #{role.name} (#{role.slug})"
  end
else
  puts "    ✓ All roles with scope requirements are properly configured"
end

# Verificar exclusividad (un rol no puede permitir ambos tipos según tu modelo)
# Si decides permitir roles híbridos en el futuro, comenta esta validación
both_scopes = Role.where(allows_node_scope: true, allows_vehicle_scope: true)
if both_scopes.any?
  puts "    ⚠️  WARNING: #{both_scopes.count} roles allow both scope types (hybrid roles):"
  both_scopes.each do |role|
    puts "       - #{role.name} (#{role.slug})"
  end
end

puts "\n✅ Roles seed completed!"
