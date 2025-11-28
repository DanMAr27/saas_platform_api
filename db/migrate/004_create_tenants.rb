# frozen_string_literal: true

# db/seeds/04_tenants.rb
# Tenants con diferentes estados, planes y membresías
# INCLUYE EJEMPLOS DE USUARIOS CON MÚLTIPLES ROLES

puts "\n🏢 Creating Tenants..."

# Roles
admin_role = Role.find_by!(slug: 'tenant_admin')
manager_role = Role.find_by!(slug: 'tenant_manager')
driver_role = Role.find_by!(slug: 'tenant_driver')
viewer_role = Role.find_by(slug: 'tenant_viewer')

# ============================================
# TENANT 1: ACME CORP (Con usuarios multi-rol)
# ============================================

puts "\n  Creating Trial Tenant with Multi-Role Users:"

acme = Tenant.create_with(
  name: 'Acme Corporation',
  legal_name: 'Acme Corporation S.L.',
  tax_id: 'B12345678',
  domain: 'acme.example.com',
  address: 'Calle Mayor 123',
  city: 'Madrid',
  state: 'Madrid',
  postal_code: '28013',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'trial',
  plan: 'trial',
  trial_ends_at: 20.days.from_now,
  max_users: 5,
  max_storage_gb: 10,
  settings: {
    features_enabled: %w[fleet_management basic_reporting]
  }
).find_or_create_by!(slug: 'acme-corp')

puts "    ✓ Acme Corporation (TRIAL - expires in 20 days)"

# Admin principal
acme_admin = User.create_with(
  first_name: 'María',
  last_name: 'García',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111111',
  email_verified_at: Time.current
).find_or_create_by!(email: 'maria.garcia@acme.com')

TenantMembership.create_with(
  tenant: acme,
  role: admin_role,
  status: 'active',
  is_primary_admin: true,
  is_default: true
).find_or_create_by!(user: acme_admin, role: admin_role)

puts "      Admin: maria.garcia@acme.com (primary admin)"

# MULTI-ROL: Carlos es Manager Y Driver
carlos = User.create_with(
  first_name: 'Carlos',
  last_name: 'López',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111112',
  email_verified_at: Time.current
).find_or_create_by!(email: 'carlos.lopez@acme.com')

# Rol de Manager
TenantMembership.create_with(
  tenant: acme,
  role: manager_role,
  status: 'active',
  created_by: acme_admin.id
).find_or_create_by!(user: carlos, role: manager_role)

# Rol de Driver (mismo usuario, diferente rol)
TenantMembership.create_with(
  tenant: acme,
  role: driver_role,
  status: 'active',
  created_by: acme_admin.id
).find_or_create_by!(user: carlos, role: driver_role)

puts "      Manager + Driver: carlos.lopez@acme.com (2 roles)"
puts "        - #{manager_role.name}"
puts "        - #{driver_role.name}"

# Driver puro (solo un rol)
ana = User.create_with(
  first_name: 'Ana',
  last_name: 'Rodríguez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111113',
  email_verified_at: Time.current
).find_or_create_by!(email: 'ana.rodriguez@acme.com')

TenantMembership.create_with(
  tenant: acme,
  role: driver_role,
  status: 'active',
  created_by: acme_admin.id
).find_or_create_by!(user: ana, role: driver_role)

puts "      Driver: ana.rodriguez@acme.com"

# ============================================
# TENANT 2: GLOBAL LOGISTICS (Equipo completo multi-rol)
# ============================================

puts "\n  Creating Professional Tenant with Complex Multi-Role Setup:"

logistics = Tenant.create_with(
  name: 'Global Logistics Pro',
  legal_name: 'Global Logistics Pro S.A.',
  tax_id: 'A11223344',
  domain: 'globallogistics.example.com',
  address: 'Avenida Diagonal 500',
  city: 'Barcelona',
  state: 'Catalonia',
  postal_code: '08006',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'active',
  plan: 'professional',
  subscription_starts_at: 1.year.ago,
  subscription_ends_at: 1.year.from_now,
  max_users: 50,
  max_storage_gb: 200
).find_or_create_by!(slug: 'global-logistics')

puts "    ✓ Global Logistics Pro (ACTIVE - Professional Plan)"

# Admin principal
logistics_admin = User.create_with(
  first_name: 'Patricia',
  last_name: 'Torres',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600333333',
  email_verified_at: 1.year.ago
).find_or_create_by!(email: 'patricia.torres@globallogistics.com')

TenantMembership.create_with(
  tenant: logistics,
  role: admin_role,
  status: 'active',
  is_primary_admin: true,
  is_default: true
).find_or_create_by!(user: logistics_admin, role: admin_role)

puts "      Admin: patricia.torres@globallogistics.com"

# Manager que también supervisa como viewer en otras áreas
david = User.create_with(
  first_name: 'David',
  last_name: 'Moreno',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600333334',
  email_verified_at: rand(1..11).months.ago
).find_or_create_by!(email: 'david.moreno@globallogistics.com')

TenantMembership.create_with(
  tenant: logistics,
  role: manager_role,
  status: 'active',
  created_by: logistics_admin.id
).find_or_create_by!(user: david, role: manager_role)

if viewer_role
  TenantMembership.create_with(
    tenant: logistics,
    role: viewer_role,
    status: 'active',
    created_by: logistics_admin.id
  ).find_or_create_by!(user: david, role: viewer_role)

  puts "      Manager + Viewer: david.moreno@globallogistics.com (2 roles)"
end

# Manager que ocasionalmente conduce
laura = User.create_with(
  first_name: 'Laura',
  last_name: 'Sánchez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600333335',
  email_verified_at: rand(1..11).months.ago
).find_or_create_by!(email: 'laura.sanchez@globallogistics.com')

TenantMembership.create_with(
  tenant: logistics,
  role: manager_role,
  status: 'active',
  created_by: logistics_admin.id
).find_or_create_by!(user: laura, role: manager_role)

TenantMembership.create_with(
  tenant: logistics,
  role: driver_role,
  status: 'active',
  created_by: logistics_admin.id
).find_or_create_by!(user: laura, role: driver_role)

puts "      Manager + Driver: laura.sanchez@globallogistics.com (2 roles)"

# Coordinador que también gestiona flota (usando custom role)
fleet_coordinator_role = Role.find_by(slug: 'fleet_coordinator')
if fleet_coordinator_role
  miguel = User.create_with(
    first_name: 'Miguel',
    last_name: 'Torres',
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: '+34600333336',
    email_verified_at: rand(1..11).months.ago
  ).find_or_create_by!(email: 'miguel.torres@globallogistics.com')

  TenantMembership.create_with(
    tenant: logistics,
    role: fleet_coordinator_role,
    status: 'active',
    created_by: logistics_admin.id
  ).find_or_create_by!(user: miguel, role: fleet_coordinator_role)

  TenantMembership.create_with(
    tenant: logistics,
    role: manager_role,
    status: 'active',
    created_by: logistics_admin.id
  ).find_or_create_by!(user: miguel, role: manager_role)

  puts "      Fleet Coordinator + Manager: miguel.torres@globallogistics.com (2 roles)"
end

# 5 Drivers puros (solo driver)
5.times do |i|
  driver_user = User.create_with(
    first_name: "Driver",
    last_name: "#{i + 1}",
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3460033#{3350 + i}",
    email_verified_at: rand(1..6).months.ago
  ).find_or_create_by!(email: "driver#{i + 1}@globallogistics.com")

  TenantMembership.create_with(
    tenant: logistics,
    role: driver_role,
    status: 'active',
    created_by: logistics_admin.id
  ).find_or_create_by!(user: driver_user, role: driver_role)
end

puts "      Drivers: 5 pure drivers (single role each)"

# ============================================
# VERIFICACIÓN DE MULTI-ROL
# ============================================

puts "\n  🔍 Multi-Role Verification:"

# Verificar Carlos (Acme)
if carlos
  roles = carlos.role_slugs_in_tenant(acme)
  puts "    Carlos López (Acme):"
  puts "      - Roles: #{roles.join(', ')}"
  puts "      - Can manage: #{carlos.can_manage_in_tenant?(acme)}"
  puts "      - Can drive: #{carlos.driver_in_tenant?(acme)}"
end

# Verificar Laura (Global Logistics)
if laura
  roles = laura.role_slugs_in_tenant(logistics)
  puts "    Laura Sánchez (Global Logistics):"
  puts "      - Roles: #{roles.join(', ')}"
  puts "      - Can manage: #{laura.can_manage_in_tenant?(logistics)}"
  puts "      - Can drive: #{laura.driver_in_tenant?(logistics)}"
end

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Tenants Summary:"
puts "    - Total Tenants: #{Tenant.count}"
puts "    - By Status:"
puts "      - Trial: #{Tenant.trial.count}"
puts "      - Active: #{Tenant.active.count}"

puts "\n  👥 Tenant Memberships Summary:"
puts "    - Total Memberships: #{TenantMembership.count}"
puts "    - Active: #{TenantMembership.active.count}"
puts "    - By Role:"
puts "      - Admins: #{TenantMembership.admins.count}"
puts "      - Managers: #{TenantMembership.managers.count}"
puts "      - Drivers: #{TenantMembership.drivers.count}"

# Multi-role stats
total_users_with_memberships = TenantMembership.active.distinct.count(:user_id)
total_memberships = TenantMembership.active.count
users_with_multiple_roles = TenantMembership.active
  .group(:user_id, :tenant_id)
  .having('COUNT(*) > 1')
  .count
  .keys
  .count

puts "\n  🎭 Multi-Role Statistics:"
puts "    - Users with memberships: #{total_users_with_memberships}"
puts "    - Total role assignments: #{total_memberships}"
puts "    - Users with multiple roles in same tenant: #{users_with_multiple_roles}"

# Detalles de usuarios multi-rol
puts "\n  📋 Users with Multiple Roles:"
TenantMembership.active
  .group(:user_id, :tenant_id)
  .having('COUNT(*) > 1')
  .count
  .each do |(user_id, tenant_id), role_count|
    user = User.find(user_id)
    tenant = Tenant.find(tenant_id)
    roles = user.role_slugs_in_tenant(tenant)

    puts "    #{user.email} (#{tenant.name}):"
    puts "      - #{role_count} roles: #{roles.join(', ')}"
  end
