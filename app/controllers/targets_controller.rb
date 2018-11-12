class TargetsController < ApplicationController
  before_action :authenticate_founder!

  # GET /targets/:id/download_rubric
  def download_rubric
    target = Target.find(params[:id])
    authorize target
    redirect_to target.rubric_url
  end

  # GET /targets/select2_search
  def select2_search
    raise_not_found if true_user.admin_user.blank?
    render json: Targets::Select2SearchService.search_for_target(params[:q])
  end

  # GET /targets/:id/prerequisite_targets
  def prerequisite_targets
    target = Target.find(params[:id])
    authorize target

    prerequisite_targets = target.prerequisite_targets.each_with_object({}) do |p_target, hash|
      status = Targets::StatusService.new(p_target, current_founder).status
      next if status.in? [Target::STATUS_COMPLETE, Target::STATUS_NEEDS_IMPROVEMENT]

      hash[p_target.id] = p_target.title
    end
    render json: prerequisite_targets
  end

  # GET /targets/:id/startup_feedback
  def startup_feedback
    target = Target.find(params[:id])
    authorize target

    latest_feedback = Targets::FeedbackService.new(target, current_founder).feedback_for_latest_event

    startup_feedback = latest_feedback.each_with_object({}) do |feedback, hash|
      hash[feedback.id] = feedback.feedback
    end

    render json: startup_feedback
  end

  # GET /targets/:id/details
  def details
    target = Target.find(params[:id])
    authorize target

    render json: Targets::OverlayDetailsService.new(target, current_founder).all_details
  end

  # POST /targets/:id/auto_verify
  def auto_verify
    target = Target.find(params[:id])
    Targets::AutoVerificationService.new(target, current_founder).auto_verify
    head :ok
  end
end
