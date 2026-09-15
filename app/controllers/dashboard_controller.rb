# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @date    = requested_date
    @metrics = Metrics.new(@date).build
  end
end
