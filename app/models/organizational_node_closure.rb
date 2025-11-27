# app/models/organizational_node_closure.rb
# Tabla de closure para queries jerárquicas eficientes

class OrganizationalNodeClosure < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :ancestor, class_name: "OrganizationalNode"
  belongs_to :descendant, class_name: "OrganizationalNode"

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :ancestor_id, presence: true
  validates :descendant_id, presence: true
  validates :depth, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ============================================
  # SCOPES
  # ============================================
  scope :direct_children, -> { where(depth: 1) }
  scope :self_references, -> { where("ancestor_id = descendant_id") }
  scope :excluding_self, -> { where("ancestor_id != descendant_id") }

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Reconstruir toda la closure table (útil para migraciones)
    def rebuild!
      transaction do
        delete_all

        OrganizationalNode.find_each do |node|
          # Self-reference
          create!(ancestor_id: node.id, descendant_id: node.id, depth: 0)

          # Ancestros
          node.parent&.ancestor_closures&.each do |closure|
            create!(
              ancestor_id: closure.ancestor_id,
              descendant_id: node.id,
              depth: closure.depth + 1
            )
          end
        end
      end
    end

    # Verificar integridad
    def verify_integrity
      errors = []

      # Verificar que todos los nodos tienen self-reference
      OrganizationalNode.find_each do |node|
        unless exists?(ancestor_id: node.id, descendant_id: node.id, depth: 0)
          errors << "Missing self-reference for node #{node.id}"
        end
      end

      errors
    end
  end
end
