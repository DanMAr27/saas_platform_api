# frozen_string_literal: true

# db/seeds/04_tenants.rb
# Tenants con diferentes estados, planes y membresías

puts "\n🏢 Creating Tenants..."

# Roles
admin_role = Role.find_by!(slug: 'tenant_admin')
manager_role = Role.find_by!(slug: 'tenant_manager')
driver_role = Role.find_by!(slug: 'tenant_driver')
viewer_role = Role.find_by(slug: 'tenant_viewer')

# Usuarios existentes para agregar a tenants
john = User.find_by(email: 'john.doe@example.com')
jane = User.find_by(email: 'jane.smith@example.com')
carlos = User.find_by(email: 'carlos.garcia@example.com')

# ============================================
# TENANT 1: TRIAL (Acme Corp)
# ============================================

puts "\n  Creating Trial Tenant:"

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
    features_enabled: %w[fleet_management basic_reporting],
    notifications_enabled: true,
    theme: 'light'
  },
  metadata: {
    industry: 'logistics',
    company_size: 'small',
    onboarding_completed: false
  }
).find_or_create_by!(slug: 'acme-corp')

puts "    ✓ Acme Corporation (TRIAL - expires in 20 days)"

# Admin de Acme
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
  is_default: true,
  created_by: acme_admin.id
).find_or_create_by!(user: acme_admin)

puts "      Admin: maria.garcia@acme.com"

# Manager de Acme
acme_manager = User.create_with(
  first_name: 'Carlos',
  last_name: 'López',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111112',
  email_verified_at: Time.current
).find_or_create_by!(email: 'carlos.lopez@acme.com')

TenantMembership.create_with(
  tenant: acme,
  role: manager_role,
  status: 'active',
  created_by: acme_admin.id
).find_or_create_by!(user: acme_manager)

puts "      Manager: carlos.lopez@acme.com"

# Driver de Acme (invitado, no aceptado)
acme_driver = User.create_with(
  first_name: 'Ana',
  last_name: 'Rodríguez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111113'
).find_or_create_by!(email: 'ana.rodriguez@acme.com')

TenantMembership.create_with(
  tenant: acme,
  role: driver_role,
  status: 'invited',
  invitation_token: SecureRandom.hex(32),
  invitation_sent_at: 2.days.ago,
  created_by: acme_admin.id
).find_or_create_by!(user: acme_driver)

puts "      Driver: ana.rodriguez@acme.com (INVITED - pending)"

# ============================================
# TENANT 2: ACTIVE - BASIC PLAN
# ============================================

puts "\n  Creating Active Tenant (Basic Plan):"

techstart = Tenant.create_with(
  name: 'Tech Startup Inc',
  legal_name: 'Tech Startup Inc.',
  tax_id: 'B87654321',
  domain: 'techstartup.example.com',
  address: 'Passeig de Gràcia 100',
  city: 'Barcelona',
  state: 'Catalonia',
  postal_code: '08008',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'ca',
  currency: 'EUR',
  status: 'active',
  plan: 'basic',
  subscription_starts_at: 3.months.ago,
  subscription_ends_at: 9.months.from_now,
  max_users: 10,
  max_storage_gb: 50,
  settings: {
    features_enabled: %w[fleet_management advanced_reporting api_access],
    notifications_enabled: true,
    theme: 'dark'
  }
).find_or_create_by!(slug: 'tech-startup')

puts "    ✓ Tech Startup Inc (ACTIVE - Basic Plan)"

# Admin
tech_admin = User.create_with(
  first_name: 'Joan',
  last_name: 'Martínez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600222222',
  email_verified_at: 3.months.ago
).find_or_create_by!(email: 'joan.martinez@techstartup.com')

TenantMembership.create_with(
  tenant: techstart,
  role: admin_role,
  status: 'active',
  is_primary_admin: true,
  is_default: true
).find_or_create_by!(user: tech_admin)

# Agregar John como manager
if john
  TenantMembership.create_with(
    tenant: techstart,
    role: manager_role,
    status: 'active',
    created_by: tech_admin.id
  ).find_or_create_by!(user: john)
  puts "      Manager: john.doe@example.com"
end

puts "      Admin: joan.martinez@techstartup.com"

# ============================================
# TENANT 3: ACTIVE - PROFESSIONAL PLAN
# ============================================

puts "\n  Creating Active Tenant (Professional Plan):"

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
  max_storage_gb: 200,
  settings: {
    features_enabled: %w[fleet_management advanced_reporting api_access custom_integrations multi_location],
    notifications_enabled: true
  }
).find_or_create_by!(slug: 'global-logistics')

puts "    ✓ Global Logistics Pro (ACTIVE - Professional Plan)"

# Team completo
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
).find_or_create_by!(user: logistics_admin)

# 3 Managers
[ 'david.moreno', 'laura.sanchez', 'miguel.torres' ].each_with_index do |username, index|
  manager = User.create_with(
    first_name: username.split('.').first.capitalize,
    last_name: username.split('.').last.capitalize,
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3460033#{3340 + index}",
    email_verified_at: rand(1..11).months.ago
  ).find_or_create_by!(email: "#{username}@globallogistics.com")

  TenantMembership.create_with(
    tenant: logistics,
    role: manager_role,
    status: 'active',
    created_by: logistics_admin.id
  ).find_or_create_by!(user: manager)
end

puts "      Admin: patricia.torres@globallogistics.com"
puts "      Managers: 3 active"

# 5 Drivers
5.times do |i|
  driver = User.create_with(
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
  ).find_or_create_by!(user: driver)
end

puts "      Drivers: 5 active"

# ============================================
# TENANT 4: SUSPENDED
# ============================================

puts "\n  Creating Suspended Tenant:"

suspended = Tenant.create_with(
  name: 'Suspended Company Ltd',
  legal_name: 'Suspended Company Ltd',
  tax_id: 'B99887766',
  address: 'Calle Suspended 999',
  city: 'Valencia',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'suspended',
  plan: 'basic',
  subscription_starts_at: 6.months.ago,
  metadata: {
    suspension_reason: 'Payment overdue',
    suspended_at: 1.week.ago
  }
).find_or_create_by!(slug: 'suspended-company')

suspended_admin = User.create_with(
  first_name: 'Suspended',
  last_name: 'Admin',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  email_verified_at: 6.months.ago
).find_or_create_by!(email: 'admin@suspended.com')

TenantMembership.create_with(
  tenant: suspended,
  role: admin_role,
  status: 'suspended',
  is_primary_admin: true
).find_or_create_by!(user: suspended_admin)

puts "    ✓ Suspended Company Ltd (SUSPENDED - payment issue)"

# ============================================
# TENANT 5: CANCELLED
# ============================================

puts "\n  Creating Cancelled Tenant:"

cancelled = Tenant.create_with(
  name: 'Cancelled Corp',
  legal_name: 'Cancelled Corp S.L.',
  tax_id: 'B55443322',
  country: 'ES',
  status: 'cancelled',
  plan: 'trial',
  subscription_ends_at: 2.weeks.ago,
  metadata: {
    cancellation_reason: 'Switched to competitor',
    cancelled_at: 2.weeks.ago
  }
).find_or_create_by!(slug: 'cancelled-corp')

puts "    ✓ Cancelled Corp (CANCELLED - churned)"

# ============================================
# TENANT 6: ENTERPRISE
# ============================================

puts "\n  Creating Enterprise Tenant:"

enterprise = Tenant.create_with(
  name: 'Enterprise Solutions Mega Corp',
  legal_name: 'Enterprise Solutions International S.A.',
  tax_id: 'A00112233',
  domain: 'enterprise.example.com',
  address: 'Torre Empresarial, Piso 25',
  city: 'Madrid',
  state: 'Madrid',
  postal_code: '28046',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'active',
  plan: 'enterprise',
  subscription_starts_at: 2.years.ago,
  max_users: 1000,
  max_storage_gb: 1000,
  settings: {
    features_enabled: %w[
      fleet_management
      advanced_reporting
      api_access
      custom_integrations
      multi_location
      white_label
      priority_support
      sla_99_9
    ],
    custom_domain_enabled: true,
    sso_enabled: true
  }
).find_or_create_by!(slug: 'enterprise-mega')

enterprise_admin = User.create_with(
  first_name: 'Enterprise',
  last_name: 'Admin',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34900444444',
  email_verified_at: 2.years.ago
).find_or_create_by!(email: 'admin@enterprise.com')

TenantMembership.create_with(
  tenant: enterprise,
  role: admin_role,
  status: 'active',
  is_primary_admin: true,
  is_default: true
).find_or_create_by!(user: enterprise_admin)

puts "    ✓ Enterprise Solutions Mega Corp (ACTIVE - Enterprise Plan)"

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Tenants Summary:"
puts "    - Total Tenants: #{Tenant.count}"
puts "    - By Status:"
puts "      - Trial: #{Tenant.trial.count}"
puts "      - Active: #{Tenant.active.count}"
puts "      - Suspended: #{Tenant.suspended.count}"
puts "      - Cancelled: #{Tenant.cancelled.count}"
puts "    - By Plan:"
puts "      - Trial: #{Tenant.by_plan('trial').count}"
puts "      - Basic: #{Tenant.by_plan('basic').count}"
puts "      - Professional: #{Tenant.by_plan('professional').count}"
puts "      - Enterprise: #{Tenant.by_plan('enterprise').count}"

puts "\n  👥 Tenant Memberships Summary:"
puts "    - Total Memberships: #{TenantMembership.count}"
puts "    - Active: #{TenantMembership.active.count}"
puts "    - Invited: #{TenantMembership.invited.count}"
puts "    - Suspended: #{TenantMembership.suspended.count}"
puts "    - By Role:"
puts "      - Admins: #{TenantMembership.admins.count}"
puts "      - Managers: #{TenantMembership.managers.count}"
puts "      - Drivers: #{TenantMembership.drivers.count}"

puts "\n  🏢 Tenant Access Info:"
Tenant.active.each do |tenant|
  primary_admin = tenant.primary_admin
  puts "    #{tenant.name} (#{tenant.plan})"
  puts "      Admin: #{primary_admin&.email || 'N/A'}"
  puts "      Users: #{tenant.active_memberships.count}/#{tenant.max_users}"
  puts "      Status: #{tenant.status.upcase}"
end
