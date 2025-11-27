# frozen_string_literal: true

# db/seeds/03_platform_admins.rb
# Platform admins con diferentes configuraciones

puts "\n🛡️ Creating Platform Admins..."

# Roles
super_admin_role = Role.find_by!(slug: 'super_admin')
support_admin_role = Role.find_by!(slug: 'support_admin')

# ============================================
# SUPER ADMIN PRINCIPAL
# ============================================

puts "\n  Super Admins:"

super_admin_email = ENV.fetch('SUPER_ADMIN_EMAIL', 'superadmin@saasplatform.com')
super_admin = User.create_with(
  first_name: ENV.fetch('SUPER_ADMIN_FIRST_NAME', 'Super'),
  last_name: ENV.fetch('SUPER_ADMIN_LAST_NAME', 'Admin'),
  password: ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!'),
  password_confirmation: ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!'),
  phone: '+34900000000',
  email_verified_at: 6.months.ago,
  last_login_at: 1.hour.ago,
  avatar_url: 'https://ui-avatars.com/api/?name=Super+Admin&background=dc2626&color=fff'
).find_or_create_by!(email: super_admin_email)

PlatformMembership.create_with(
  role: super_admin_role,
  context: 'platform',
  mfa_enabled: true,
  mfa_configured_at: 6.months.ago,
  can_impersonate: true,
  allowed_ips: []
).find_or_create_by!(user: super_admin)

puts "    ✓ #{super_admin_email}"
puts "      - MFA: Enabled"
puts "      - Can Impersonate: Yes"
puts "      - Password: #{ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!')}"

# ============================================
# SUPER ADMIN SECUNDARIO
# ============================================

secondary_super = User.create_with(
  first_name: 'Secondary',
  last_name: 'SuperAdmin',
  password: 'SecondaryAdmin123!',
  password_confirmation: 'SecondaryAdmin123!',
  phone: '+34900000001',
  email_verified_at: 3.months.ago,
  last_login_at: 1.week.ago
).find_or_create_by!(email: 'secondary.superadmin@saasplatform.com')

PlatformMembership.create_with(
  role: super_admin_role,
  context: 'platform',
  mfa_enabled: false,
  can_impersonate: false
).find_or_create_by!(user: secondary_super)

puts "    ✓ secondary.superadmin@saasplatform.com"
puts "      - MFA: Disabled"
puts "      - Can Impersonate: No"

# ============================================
# SUPPORT ADMINS
# ============================================

puts "\n  Support Admins:"

# Support Admin 1 - Con MFA y capacidad de impersonación
support1 = User.create_with(
  first_name: 'Support',
  last_name: 'Admin',
  password: 'SupportAdmin123!',
  password_confirmation: 'SupportAdmin123!',
  phone: '+34900001000',
  email_verified_at: 4.months.ago,
  last_login_at: 2.days.ago,
  avatar_url: 'https://ui-avatars.com/api/?name=Support+Admin&background=2563eb&color=fff'
).find_or_create_by!(email: 'support@saasplatform.com')

PlatformMembership.create_with(
  role: support_admin_role,
  context: 'platform',
  mfa_enabled: true,
  mfa_configured_at: 4.months.ago,
  can_impersonate: true,
  last_impersonation_at: 5.days.ago
).find_or_create_by!(user: support1)

puts "    ✓ support@saasplatform.com"
puts "      - MFA: Enabled (required)"
puts "      - Can Impersonate: Yes"
puts "      - Last Impersonation: 5 days ago"

# Support Admin 2 - Sin capacidad de impersonación
support2 = User.create_with(
  first_name: 'Junior',
  last_name: 'Support',
  password: 'JuniorSupport123!',
  password_confirmation: 'JuniorSupport123!',
  phone: '+34900001001',
  email_verified_at: 1.month.ago,
  last_login_at: 12.hours.ago
).find_or_create_by!(email: 'junior.support@saasplatform.com')

PlatformMembership.create_with(
  role: support_admin_role,
  context: 'platform',
  mfa_enabled: true,
  mfa_configured_at: 1.month.ago,
  can_impersonate: false
).find_or_create_by!(user: support2)

puts "    ✓ junior.support@saasplatform.com"
puts "      - MFA: Enabled (required)"
puts "      - Can Impersonate: No"

# Support Admin 3 - Con IPs permitidas
support3 = User.create_with(
  first_name: 'Restricted',
  last_name: 'Support',
  password: 'RestrictedSupport123!',
  password_confirmation: 'RestrictedSupport123!',
  phone: '+34900001002',
  email_verified_at: 2.months.ago,
  last_login_at: 1.day.ago
).find_or_create_by!(email: 'restricted.support@saasplatform.com')

PlatformMembership.create_with(
  role: support_admin_role,
  context: 'platform',
  mfa_enabled: true,
  mfa_configured_at: 2.months.ago,
  can_impersonate: true,
  allowed_ips: [ '192.168.1.100', '10.0.0.50' ]
).find_or_create_by!(user: support3)

puts "    ✓ restricted.support@saasplatform.com"
puts "      - MFA: Enabled"
puts "      - Can Impersonate: Yes"
puts "      - Allowed IPs: 192.168.1.100, 10.0.0.50"

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Platform Admins Summary:"
puts "    - Total Platform Memberships: #{PlatformMembership.count}"
puts "    - Super Admins: #{PlatformMembership.super_admins.count}"
puts "    - Support Admins: #{PlatformMembership.support_admins.count}"
puts "    - With MFA Enabled: #{PlatformMembership.with_mfa.count}"
puts "    - Can Impersonate: #{PlatformMembership.can_impersonate.count}"

puts "\n  🔑 Platform Admin Credentials:"
puts "    1. Super Admin:"
puts "       - Email: #{super_admin_email}"
puts "       - Password: #{ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!')}"
puts "    2. Support Admin:"
puts "       - Email: support@saasplatform.com"
puts "       - Password: SupportAdmin123!"
puts "    3. Junior Support:"
puts "       - Email: junior.support@saasplatform.com"
puts "       - Password: JuniorSupport123!"
