# frozen_string_literal: true

puts "\n==== Seeding Tenants (Phase 2) ===="

# ============================================
# ROLES (tenant roles)
# ============================================

admin_role   = Role.find_by!(slug: "tenant_admin")
manager_role = Role.find_by!(slug: "tenant_manager")
driver_role  = Role.find_by!(slug: "tenant_driver")

# ============================================
# TENANT 1: Acme Corp (Trial)
# ============================================

tenant1_result = Platform::Tenants::CreateService.call(
  params: {
    name: 'Acme Corporation',
    slug: 'acme-corp',
    domain: 'acme.example.com',
    legal_name: 'Acme Corporation S.L.',
    tax_id: 'B12345678',
    address: 'Calle Mayor 123',
    city: 'Madrid',
    country: 'ES',
    timezone: 'Europe/Madrid',
    locale: 'es',
    status: 'trial',
    plan: 'trial',
    admin_email: 'admin@acme.example.com',
    admin_first_name: 'María',
    admin_last_name: 'García',
    admin_password: 'Password123!',
    admin_phone: '+34600111111',
    admin_role_id: admin_role.id
  }
)

if tenant1_result.success?
  tenant1 = tenant1_result.data[:tenant]
  admin1  = tenant1_result.data[:admin]
  puts "✓ Created tenant: #{tenant1.name} (Admin: #{admin1.email})"
else
  puts "✗ Failed to create Acme Corp:"
  pp tenant1_result.errors
  tenant1 = Tenant.find_by(slug: "acme-corp")
end

# ============================================
# TENANT 2: Tech Startup (Active)
# ============================================

tenant2_result = Platform::Tenants::CreateService.call(
  params: {
    name: 'Tech Startup Inc',
    slug: 'tech-startup',
    domain: 'techstartup.example.com',
    legal_name: 'Tech Startup Inc.',
    tax_id: 'B87654321',
    address: 'Passeig de Gràcia 100',
    city: 'Barcelona',
    country: 'ES',
    timezone: 'Europe/Madrid',
    locale: 'ca',
    status: 'active',
    plan: 'professional',
    admin_email: 'ceo@techstartup.example.com',
    admin_first_name: 'Joan',
    admin_last_name: 'Martínez',
    admin_password: 'Password123!',
    admin_phone: '+34600222222',
    admin_role_id: admin_role.id
  }
)

if tenant2_result.success?
  tenant2 = tenant2_result.data[:tenant]
  admin2  = tenant2_result.data[:admin]
  puts "✓ Created tenant: #{tenant2.name} (Admin: #{admin2.email})"
else
  puts "✗ Failed to create Tech Startup:"
  pp tenant2_result.errors
  tenant2 = Tenant.find_by(slug: "tech-startup")
end

# ============================================
# INVITAR MANAGER Y DRIVER A ACME
# ============================================

if tenant1
  acme_admin = User.find_by(email: "admin@acme.example.com")
  if acme_admin
    # Manager
    manager_result = Platform::Tenants::InviteService.call(
      tenant: tenant1,
      params: {
        email: 'manager@acme.example.com',
        first_name: 'Carlos',
        last_name: 'López',
        phone: '+34600333333',
        role_id: manager_role.id
      },
      invited_by: acme_admin
    )
    manager_result.data[:membership].activate! if manager_result.success?

    # Driver
    driver_result = Platform::Tenants::InviteService.call(
      tenant: tenant1,
      params: {
        email: 'driver@acme.example.com',
        first_name: 'Ana',
        last_name: 'Rodríguez',
        phone: '+34600444444',
        role_id: driver_role.id
      },
      invited_by: acme_admin
    )
    driver_result.data[:membership].activate! if driver_result.success?
  end
end

# ============================================
# AGREGAR USUARIO EXISTENTE A TECH STARTUP
# ============================================

if tenant2
  john = User.find_by(email: "john.doe@example.com")
  tech_admin = User.find_by(email: "ceo@techstartup.example.com")
  if john && tech_admin
    TenantMembership.create!(
      user: john,
      tenant: tenant2,
      role: manager_role,
      status: "active",
      created_by: tech_admin.id
    )
  end
end

# ============================================
# RESUMEN
# ============================================

puts "\n==== Tenant Seeds Summary ===="
puts "Total tenants: #{Tenant.count}"
puts "Active tenants: #{Tenant.active.count}"
puts "Trial tenants: #{Tenant.trial.count}"
puts "1. Acme Corporation (Trial) - Admin: admin@acme.example.com"
puts "2. Tech Startup Inc (Active) - Admin: ceo@techstartup.example.com"
