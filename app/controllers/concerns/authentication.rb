# frozen_string_literal: true

# Database-backed sessions, adapted from Rails 8's authentication generator: each Session
# row is independently revocable and the signed cookie carries only its id. Identity is
# proven by the verified NIP-98 event at sign-in (Sessions::Authenticate), never by the
# cookie alone.
#
# Rails 8's generator requires auth by default; Switchboard's catalog is public, so this is
# inverted: resume_session always runs (to expose current_user for the menu), and an action
# opts INTO protection with `before_action :require_login`.
module Authentication
	extend ActiveSupport::Concern

	included do
		before_action :resume_session
		helper_method :current_user, :signed_in?
	end

	private

	def resume_session
		Current.session ||= find_session_by_cookie
	end

	def find_session_by_cookie
		Session.active.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
	end

	def current_user = Current.user
	def signed_in? = Current.session.present?

	def require_login
		redirect_to root_path unless signed_in?
	end

	# Creates a revocable Session row; the signed, httponly cookie holds only its id.
	def start_new_session_for(user)
		new_session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
		Current.session = new_session
		cookie = { value: new_session.id, httponly: true, secure: Rails.env.production?, same_site: :lax }
		cookies.signed[:session_id] = cookie.merge(expires: Session::MAX_AGE.from_now)
		new_session
	end

	def terminate_session
		Current.session&.destroy
		cookies.delete(:session_id)
	end
end
