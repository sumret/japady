class SessionsController < ApplicationController
  def new; end

  def create
    email = params[:session][:email].downcase
    password = params[:session][:password]

    if login(email, password)
      flash[:success] = 'ログインに成功しました。'
      redirect_to @user
    else
      flash.now[:danger] = 'ログインに失敗しました'
      render :new
    end
  end

  def destroy
    session[:user_id] = nil

    # facebook ログイン情報の削除
    delete_facebook_session

    flash[:success] = 'ログアウトしました'
    redirect_to root_url
  end

  def facebook_login
    client_id = '534002854713007'
    redirect_uri = 'https://japady.herokuapp.com/auth/facebook/callback'
    session[:fb_state] = SecureRandom.alphanumeric

    endpoint = 'https://www.facebook.com/v11.0/dialog/oauth?'
    if session[:reauth]
      params = {
        'client_id' => client_id,
        'redirect_uri' => redirect_uri,
        'auth_type' => 'rerequest',
        'scope' => 'email'
      }
      session[:reauth] = nil
    else
      params = {
        'client_id' => '534002854713007',
        'redirect_uri' => 'https://japady.herokuapp.com/auth/facebook/callback',
        'state' => session[:facebook_state],
        'responce_type' => 'code',
        'scope' => 'email'
      }
    end

    @facebook_login_url = URI(endpoint + params.map { |k, v| "#{k}=#{v}" }.join('&'))
  end

  # facebookからの認可コード受け取り
  def facebook_callback
    @params = params
    if (error = params[:error_reason])
      # ユーザーによって拒否された場合
      # error_reason=user_denied
      # &error=access_denied
      # &error_description=Permissions+error.

      flash[:danger] = 'Facebookログインが許可されませんでした。パスワードによるログインを行うか再度Facebookログイン画面でメールアドレスを含むアクセス許可を行ってください。'
      redirect_to auth_facebook_login_path

    elsif (code = params[:code])
      # stateの確認 CSRF対策
      return if params[:state] != session[:facebook_state]

      # codeを入手できたので削除
      session[:fb_state] = nil

      require 'net/http'
      facebook_client_id = '534002854713007'

      # １．コールバックで得た認可コードをアクセストークンと交換
      uri = URI('https://graph.facebook.com/v11.0/oauth/access_token?' +
      {
        'client_id' => facebook_client_id,
        'redirect_uri' => 'https://japady.herokuapp.com/auth/facebook/callback',
        'client_secret' => ENV['FACEBOOK_API_SECRET'],
        'code' => code
      }.map { |k, v| "#{k}=#{v}" }.join('&'))

      token_info = JSON.parse(Net::HTTP.get(uri))
      user_token = token_info['access_token']
      expires_in = token_info['expires_in']
      @response_data = token_info # デバッグ用

      # ２．アクセストークンの検査 -> アクセストークン情報を取得
      uri2 = URI('https://graph.facebook.com/debug_token?' +
      {
        'input_token' => user_token,
        'access_token' => "#{facebook_client_id}|#{ENV['FACEBOOK_API_SECRET']}"
      }.map { |k, v| "#{k}=#{v}" }.join('&'))

      token_info_checked = JSON.parse(Net::HTTP.get(uri2))
      uid = token_info_checked['data']['user_id']
      @response_data2 = token_info_checked # デバッグ用

      # ３．アクセストークンを使ってユーザー情報を取得
      uri3 = URI("https://graph.facebook.com/#{uid}?" +
      {
        'fields' => 'id,name,email',
        'access_token' => user_token
      }.map { |k, v| "#{k}=#{v}" }.join('&'))

      user_info = JSON.parse(Net::HTTP.get(uri3))
      @response_data3 = user_info # デバッグ用

      if (@user = User.find_by(uid: uid))

        # 既存ユーザーならログイン
        session[:user_id] = @user.id
        redirect_to dashboard_path

      elsif (@user = User.find_by(email: user_info['email']))

        # 既存ユーザーかつfacebookログインは初ならfacebook情報をレコードに保管
        if @user.uid.blank?
          @user.uid = uid
          @user.save
          flash[:success] = 'Facebookユーザーと連携しました。'
        end
        # メールアドレスで検索して、別のUIDを保持しているケースはあるか。
        # 空であるケース
        # 既存ユーザーが別のアドレスのfacebookログインを使いたい場合 facebookのメールアドレスは無視してuidだけ格納する
        # 次回から１つめの分岐でログインできる。

        session[:user_id] = @user.id
        redirect_to dashboard_path

      elsif user_info['email']
        @user = User.new
        @user.uid = uid
        @user.name = user_info['name']
        @user.nickname = user_info['name']
        @user.email = user_info['email']
        @user.password = SecureRandom.alphanumeric(20)

        if User.count.zero?
          @user.member = true
          @user.manager = true
          @user.admin = true
        end

        if @user.save

          flash[:success] = 'Facebookユーザーを登録しました。'
          # begin session
          session[:user_id] = @user.id

          redirect_to @user
        else
          @mydata = user_info['id', 'name', 'email']
          render :test_facebook

        end
      else
        flash[:danger] = 'パスワードによるログインを行うか再度Facebookログイン画面でメールアドレスを含むアクセス許可を行ってください。'
        session[:reauth] = true
        redirect_to auth_facebook_login_path
      end

    end

    # *** OAutuのstate パラメータ作成 => 済
    # *** session変数へのトークン、期限、UID格納 => 済
    # *** UserモデルのSNSログイン用のID格納用カラム追加 => 済
    # *** 既存ユーザーの場合のユーザー情報更新 => 済
    # *** 新規ユーザーの場合のユーザー情報作成 => 済
    # *** Deauthorize Callback URL, Data Deletion Request URL の対応

    # メールアドレスを照合
    # 既存なら該当のユーザーのUIDを格納
    # 新規なら新しいユーザーを

    # セッションを開始
    # フェイスブックからのログアウト方法
    # フェイスブックでのログイン状況（毎リクエスト時？）
  end

  # facebookのアプリ削除リクエスト対応
  # https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback
  def facebook_deletion
    if params[:signed_request] && verify_signature(params[:signed_request])
      signed_request = decode_data(params[:signed_request])
      puts signed_request
      
      # uidは先に消去されているので見つけることができない。
      if (user = User.find_by(uid: signed_request['user_id']))
        puts user.nickname
        confirmation_code = "japady#{user.id}"
        data = {
          'url' => "#{auth_facebook_afterdeletion_url}?confirmation_code=#{confirmation_code}",
          'confirmation_code' => confirmation_code
        }
        render json: JSON.generate(data)

        User.find_by(admin: true).notes.new(
          content: "#{user.nickname}さんが退会しました。",
          announce: true,
        ).save

        # ユーザのデータを削除
        user.destroy

      else
        render status: 404, json: { status: 404, message: "User - #{signed_request['user_id']} was not found on the Japady." }
      end

    else
      render status: :internal_server_error, json: { status: 500, message: 'Internal Server Error' }
    end
  end

  # deauthorizeの対応
  # https://developers.facebook.com/docs/facebook-login/manually-build-a-login-flow?locale=ja_JP#deauth-callback
  def facebook_deauthorize
    if params[:signed_request] && verify_signature(params[:signed_request])
      signed_request = decode_data(params[:signed_request])
      
      User.find_by(admin: true).notes.new(
        content: "#{user.nickname}さんがSNSログインを解除しました。",
        announce: true,
        ).save

      # ＊＊＊ uidを削除 - データ削除要求が来たときに探せなくなるので何もしない
      # user.update(uid: nil) if (user = User.find_by(uid: signed_request['user_id']))
    end
  end

  def facebook_after_deletion
    delete_facebook_session
    @confirmation_code = params[:confirmation_code]
  end

  private

  # 署名の確認
  def verify_signature(str)
    encoded_sig, payload = str.split('.')
    sig = base64_url_decode(encoded_sig)
    expected_sig = OpenSSL::HMAC.digest('sha256', ENV['FACEBOOK_API_SECRET'], payload)
    sig == expected_sig
  end

  # データの取得
  def decode_data(str)
    encoded_sig, payload = str.split('.')
    data = ActiveSupport::JSON.decode(base64_url_decode(payload))
  end

  def base64_url_decode(str)
    encoded_str =  str.gsub('-', '+').gsub('_', '/')
    encoded_str += '=' until (encoded_str.size % 4).zero?
    Base64.decode64(encoded_str)
  end

  def login(email, password)
    @user = User.find_by(email: email)

    return false unless @user&.authenticate(password)

    session[:user_id] = @user.id
    true
  end

  def delete_facebook_session
    session[:fb_uid] = nil
    session[:fb_user_token] = nil
    session[:fb_token_expires_in] = nil
    session[:fb_state] = nil
    session[:reauth] = nil

    session[:facebook_state] = nil # 旧パラメータ。。なくす
  end
end
