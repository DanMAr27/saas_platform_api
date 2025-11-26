# frozen_string_literal: true

# Seeds para Fase 3: Roles del sistema
# Crea el catálogo de roles base

puts "\n==== Seeding Roles (Phase 3) ===="

# ============================================
# ROLES DE PLATAFORMA
# ============================================

super_admin_role = Role.find_or_initialize_by(slug: 'super_admin')
if super_admin_role.new_record?
  super_admin_role.assign_attributes(
    name: 'Super Admin',
    description: 'Full access to the entire platform. Can manage all tenants, users, and system settings.',
    context: 'platform',
    is_system: true,
    priority: 1,
    requires_scope: false
  )
  super_admin_role.save!
  puts "✓ Created role: Super Admin (platform)"
else
  puts "⊘ Role already exists: Super Admin"
end

support_admin_role = Role.find_or_initialize_by(slug: 'support_admin')
if support_admin_role.new_record?
  support_admin_role.assign_attributes(
    name: 'Support Admin',
    description: 'Support team access. Can view and impersonate users across tenants for support purposes.',
    context: 'platform',
    is_system: true,
    priority: 2,
    requires_scope: false
  )
  support_admin_role.save!
  puts "✓ Created role: Support Admin (platform)"
else
  puts "⊘ Role already exists: Support Admin"
end

# ============================================
# ROLES DE TENANT
# ============================================

tenant_admin_role = Role.find_or_initialize_by(slug: 'tenant_admin')
if tenant_admin_role.new_record?
  tenant_admin_role.assign_attributes(
    name: 'Tenant Admin',
    description: 'Full access to the tenant. Can manage users, settings, and all resources within the tenant.',
    context: 'tenant',
    is_system: true,
    priority: 10,
    requires_scope: false
  )
  tenant_admin_role.save!
  puts "✓ Created role: Tenant Admin (tenant)"
else
  puts "⊘ Role already exists: Tenant Admin"
end

tenant_manager_role = Role.find_or_initialize_by(slug: 'tenant_manager')
if tenant_manager_role.new_record?
  tenant_manager_role.assign_attributes(
    name: 'Tenant Manager',
    description: 'Manages resources within the tenant. Can view and edit most data but cannot manage users or billing.',
    context: 'tenant',
    is_system: true,
    priority: 20,
    requires_scope: true # Managers pueden tener scopes de nodos/vehículos
  )
  tenant_manager_role.save!
  puts "✓ Created role: Tenant Manager (tenant)"
else
  puts "⊘ Role already exists: Tenant Manager"
end

tenant_driver_role = Role.find_or_initialize_by(slug: 'tenant_driver')
if tenant_driver_role.new_record?
  tenant_driver_role.assign_attributes(
    name: 'Tenant Driver',
    description: 'Basic operational access. Can view and use assigned resources but has limited editing permissions.',
    context: 'tenant',
    is_system: true,
    priority: 30,
    requires_scope: true # Drivers tienen scopes específicos de vehículos
  )
  tenant_driver_role.save!
  puts "✓ Created role: Tenant Driver (tenant)"
else
  puts "⊘ Role already exists: Tenant Driver"
end

# ============================================
# ACTUALIZAR MEMBERSHIPS EXISTENTES CON ROLE_ID
# ============================================

puts "\n==== Updating Existing Memberships with role_id ===="

# Actualizar TenantMemberships
TenantMembership.where(role_id: nil).find_each do |membership|
  role_slug = case membership.role
  when 'admin' then 'tenant_admin'
  when 'manager' then 'tenant_manager'
  when 'driver' then 'tenant_driver'
  else 'tenant_driver'
  end

  role = Role.find_by(slug: role_slug)
  if role
    membership.update_column(:role_id, role.id)
    puts "✓ Updated membership #{membership.id} with role: #{role.name}"
  end
end

# ============================================
# RESUMEN
# ============================================
puts "\n==== Roles Seeds Summary ===="
puts "Total roles: #{Role.count}"
puts "Platform roles: #{Role.platform_roles.count}"
puts "  - Super Admin"
puts "  - Support Admin"
puts "Tenant roles: #{Role.tenant_roles.count}"
puts "  - Tenant Admin"
puts "  - Tenant Manager"
puts "  - Tenant Driver"
puts "====================================\n"
