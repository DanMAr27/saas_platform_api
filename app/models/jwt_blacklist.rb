# frozen_string_literal: true

# Modelo para la lista negra de tokens JWT
# Implementa la estrategia de revocación de Devise JWT
# Cuando un usuario hace logout, su token se agrega aquí

class JwtBlacklist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  # Relación con User
  belongs_to :user

  # Validaciones
  validates :jti, presence: true, uniqueness: true
  validates :exp, presence: true

  # Scopes
  scope :expired, -> { where("exp < ?", Time.current) }
  scope :active, -> { where("exp >= ?", Time.current) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # ============================================
  # DEVISE JWT REVOCATION STRATEGY
  # ============================================

  # Revocar un token (agregar a blacklist)
  def self.jwt_revoked?(payload, user)
    # Verificar si el JTI está en la blacklist
    exists?(jti: payload["jti"])
  end

  # Agregar token a la blacklist
  def self.revoke_jwt(payload, user)
    create!(
      jti: payload["jti"],
      user_id: user.id,
      exp: Time.at(payload["exp"].to_i)
    )
  end

  # ============================================
  # MÉTODOS DE CLASE
  # ============================================

  class << self
    # Limpiar tokens expirados (para ejecutar en cron job)
    def cleanup_expired!
      expired.delete_all
    end

    # Revocar todos los tokens de un usuario
    def revoke_all_for_user!(user)
      # Esto forzará que todos los tokens del usuario sean inválidos
      # Útil cuando se cambia la contraseña o se desea forzar logout
      where(user_id: user.id).delete_all

      # Crear una entrada especial para invalidar todos los tokens futuros
      # hasta que el usuario haga login nuevamente
      create!(
        jti: "revoke_all_#{user.id}_#{Time.current.to_i}",
        user_id: user.id,
        exp: 30.days.from_now # Tiempo suficiente para que expiren todos los tokens
      )
    end

    # Estadísticas
    def stats
      {
        total: count,
        active: active.count,
        expired: expired.count
      }
    end
  end

  # ============================================
  # MÉTODOS DE INSTANCIA
  # ============================================

  # Verificar si el token está expirado
  def expired?
    exp < Time.current
  end

  # Información del token para debugging
  def token_info
    {
      jti: jti,
      user_email: user.email,
      expires_at: exp,
      expired: expired?,
      revoked_at: created_at
    }
  end
end
