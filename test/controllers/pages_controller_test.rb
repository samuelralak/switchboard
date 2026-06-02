require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders the home page at root" do
    get root_url
    assert_response :success
  end
end
