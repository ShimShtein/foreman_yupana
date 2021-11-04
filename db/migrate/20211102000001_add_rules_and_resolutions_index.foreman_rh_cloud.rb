class AddRulesAndResolutionsIndex < ActiveRecord::Migration[5.2]
  def change
    add_index :insights_rules, [:rule_id], unique: true
    add_index :insights_resolutions, [:rule_id, :description], unique: true
  end
end
