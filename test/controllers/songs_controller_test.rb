require "test_helper"

class SongsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @song = songs(:one)
  end

  test "should get index" do
    get songs_url
    assert_response :success
  end

  test "should get new" do
    get new_song_url
    assert_response :success
  end

  test "should create song" do
    assert_difference("Song.count") do
      post songs_url, params: { song: { artist: @song.artist, dance_id: @song.dance_id, order: @song.order+9, title: @song.title+'x' } }
    end

    assert_redirected_to song_url(Song.last)
  end

  test "should show song" do
    get song_url(@song)
    assert_response :success
  end

  test "should get edit" do
    get edit_song_url(@song)
    assert_response :success
  end

  test "should update song" do
    patch song_url(@song), params: { song: { artist: @song.artist, dance_id: @song.dance_id, order: @song.order, title: @song.title } }
    assert_redirected_to song_url(@song)
  end

  test "should destroy song" do
    dance = @song.dance

    assert_difference("Song.count", -1) do
      delete song_url(@song)
    end

    assert_redirected_to dance_songlist_url(dance)
  end
end
