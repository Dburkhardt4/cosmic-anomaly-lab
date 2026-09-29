class HomeController < ApplicationController
  def index
    @datasets = Dataset.order(updated_at: :desc).limit(5)
  end
end
