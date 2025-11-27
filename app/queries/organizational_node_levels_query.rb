# app/queries/organizational_node_levels_query.rb

class OrganizationalNodeLevelsQuery
  attr_reader :relation, :params

  def initialize(relation = OrganizationalNodeLevel.all, params: {})
    @relation = relation
    @params = params
  end

  def call
    @relation = apply_filters(@relation)
    @relation = apply_sorting(@relation)
    @relation
  end

  private

  def apply_filters(relation)
    relation = relation.where(is_system: params[:is_system]) if params.key?(:is_system)
    relation = relation.where(allows_vehicles: true) if params[:allows_vehicles]
    relation = relation.where(allows_users: true) if params[:allows_users]
    relation
  end

  def apply_sorting(relation)
    case params[:sort]
    when "name"
      relation.order(name: :asc)
    else
      relation.by_order
    end
  end
end
