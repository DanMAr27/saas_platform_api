# app/queries/vehicles_query.rb

class VehiclesQuery
  attr_reader :relation, :params, :user

  def initialize(relation = Vehicle.all, params: {}, user: nil)
    @relation = relation.extending(Scopes)
    @params = params
    @user = user
  end

  def call
    @relation = apply_filters(@relation)
    @relation = apply_search(@relation)
    @relation = apply_sorting(@relation)
    @relation
  end

  private

  def apply_filters(relation)
    relation = relation.where(status: params[:status]) if params[:status]
    relation = relation.where(vehicle_type: params[:vehicle_type]) if params[:vehicle_type]
    relation = relation.where(organizational_node_id: params[:node_id]) if params[:node_id]

    # Filtrar por scopes del usuario si no es admin
    if user && !user.platform_admin? && !user.tenant_admin?(relation.first&.tenant_id)
      relation = relation.accessible_by_user(user)
    end

    relation
  end

  def apply_search(relation)
    return relation unless params[:search].present?

    search_term = "%#{params[:search].downcase}%"
    relation.where(
      "LOWER(name) LIKE :term OR LOWER(license_plate) LIKE :term OR LOWER(fleet_number) LIKE :term",
      term: search_term
    )
  end

  def apply_sorting(relation)
    case params[:sort]
    when "name"
      relation.order(name: :asc)
    when "license_plate"
      relation.order(license_plate: :asc)
    when "recent"
      relation.order(created_at: :desc)
    else
      relation.by_name
    end
  end

  module Scopes
    def accessible_by_user(user)
      vehicle_ids = UserVehicleScope.active.where(user_id: user.id).pluck(:vehicle_id)
      where(id: vehicle_ids)
    end
  end
end
