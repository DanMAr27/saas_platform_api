# frozen_string_literal: true

# db/seeds/01_users.rb
# Seeds para Fase 1: Usuarios básicos
# Crea usuarios de prueba para testing

puts "\n==== Seeding Users (Phase 1) ===="

# Deshabilitar PaperTrail durante seeds para evitar errores de auditoría
PaperTrail.enabled = false

begin
  # ============================================
  # USUARIO DE PRUEBA 1: Verificado
  # ============================================
  user1 = User.find_or_initialize_by(email: 'john.doe@example.com')
  if user1.new_record?
    user1.assign_attributes(
      first_name: 'John',
      last_name: 'Doe',
      password: 'Password123!',
      password_confirmation: 'Password123!',
      phone: '+34600000001',
      email_verified_at: Time.current
    )
    user1.save!
    puts "✓ Created user: #{user1.email}"
  else
    puts "⊘ User already exists: #{user1.email}"
  end

  # ============================================
  # USUARIO DE PRUEBA 2: No verificado
  # ============================================
  user2 = User.find_or_initialize_by(email: 'jane.smith@example.com')
  if user2.new_record?
    user2.assign_attributes(
      first_name: 'Jane',
      last_name: 'Smith',
      password: 'Password123!',
      password_confirmation: 'Password123!',
      phone: '+34600000002',
      email_verified_at: nil # No verificado
    )
    user2.save!
    puts "✓ Created user: #{user2.email} (unverified)"
  else
    puts "⊘ User already exists: #{user2.email}"
  end

  # ============================================
  # USUARIO DE PRUEBA 3: Con invitación pendiente
  # ============================================
  user3 = User.find_or_initialize_by(email: 'invited.user@example.com')
  if user3.new_record?
    user3.assign_attributes(
      first_name: 'Invited',
      last_name: 'User',
      password: 'Password123!',
      password_confirmation: 'Password123!',
      invitation_token: SecureRandom.hex(32),
      invitation_expires_at: 7.days.from_now,
      invited_by: user1
    )
    user3.save!
    puts "✓ Created user: #{user3.email} (pending invitation)"
  else
    puts "⊘ User already exists: #{user3.email}"
  end

  # ============================================
  # USUARIO ADMINISTRADOR (para desarrollo)
  # ============================================
  admin_email = ENV.fetch('SUPER_ADMIN_EMAIL', 'admin@saasplatform.com')
  admin = User.find_or_initialize_by(email: admin_email)
  if admin.new_record?
    admin.assign_attributes(
      first_name: ENV.fetch('SUPER_ADMIN_FIRST_NAME', 'Super'),
      last_name: ENV.fetch('SUPER_ADMIN_LAST_NAME', 'Admin'),
      password: ENV.fetch('SUPER_ADMIN_PASSWORD', 'ChangeMe123!'),
      password_confirmation: ENV.fetch('SUPER_ADMIN_PASSWORD', 'ChangeMe123!'),
      phone: '+34600000000',
      email_verified_at: Time.current
    )
    admin.save!
    puts "✓ Created admin user: #{admin.email}"
    puts "  Password: #{ENV.fetch('SUPER_ADMIN_PASSWORD', 'ChangeMe123!')}"
    puts "  ⚠️  REMEMBER TO CHANGE THIS PASSWORD!"
  else
    puts "⊘ Admin user already exists: #{admin.email}"
  end

  # ============================================
  # RESUMEN
  # ============================================
  puts "\n==== User Seeds Summary ===="
  puts "Total users: #{User.count}"
  puts "Verified users: #{User.verified.count}"
  puts "Unverified users: #{User.unverified.count}"
  puts "Pending invitations: #{User.pending_invitation.count}"
  puts "\n==== Available Test Accounts ===="
  puts "1. john.doe@example.com / Password123! (verified)"
  puts "2. jane.smith@example.com / Password123! (unverified)"
  puts "3. #{admin_email} / #{ENV.fetch('SUPER_ADMIN_PASSWORD', 'ChangeMe123!')} (admin)"
  puts "====================================\n"

ensure
  # Re-habilitar PaperTrail después de las seeds
  PaperTrail.enabled = true
end
