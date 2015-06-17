class User < ActiveRecord::Base

  # TODO: friendly_id

  include Tokenable
  include Authority::UserAbilities
  include Authority::Abilities
  self.authorizer_name = 'UserAuthorizer'

  before_create :generate_fab10_coupon_code

  include Workflow

  rolify
  has_secure_password

  has_many :created_events, class_name: 'Event', foreign_key: 'creator_id'
  has_many :created_labs, class_name: 'Lab', foreign_key: 'creator_id'
  has_many :created_projects, class_name: 'Project', foreign_key: 'owner_id'
  has_many :comments, foreign_key: 'author_id'
  has_many :discussions, foreign_key: 'creator_id'
  has_many :recoveries
  has_many :role_applications
  has_many :employees
  has_one  :coupon

  has_many :academics

  has_many :created_activities, foreign_key: 'creator_id', class_name: 'Activity'
  has_many :activities, foreign_key: 'actor_id'

  has_many :contributions, foreign_key: 'contributor_id'
  has_many :projects, through: :contributions

  validates_format_of :email, :with => /\A(.+)@(.+)\z/
  validates :username, format: { :with => /\A[a-zA-Z0-9]+\z/ }, length: { minimum: 4, maximum: 30 }

  validates :first_name, :last_name, :email, :username, presence: true
  validates_uniqueness_of :email, :username, case_sensitive: false
  validates :password, presence: true, length: { minimum: 6 }, if: lambda{ !password.nil? }, on: :update
  validate :excluded_login
  def excluded_login
    if !username.blank? and Fablabs::Application.config.banned_words.include?(username.downcase)
      errors.add(:username, "is reserved")
    end
  end

  before_create { generate_token(:email_validation_hash) }
  before_create :downcase_email

  workflow do
    state :unverified do
      event :verify, transitions_to: :verified
      event :unverify, transitions_to: :unverified
    end
    state :verified do
      event :unverify, transitions_to: :unverified
    end
  end

  def avatar
    if avatar_src.present?
      avatar_src
    else
      default_url = "https://www.fablabs.io/default-user-avatar.png"
      gravatar_id = Digest::MD5.hexdigest(email.downcase)
      "https://gravatar.com/avatar/#{gravatar_id}.png?s=150&d=#{CGI.escape(default_url)}"
    end
  end

  def studied_at? lab
    academics.where(lab: lab).exists?
  end

  def employed_by? lab
    Employee.with_approved_state.where(lab: lab, user: self).exists?
  end

  def applied_to? lab
    Employee.where(lab: lab, user: self).exists?
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def to_s
    full_name
  end

  def default_locale
    locale || I18n.default_locale
  end

  def superadmin?
    has_role? :superadmin
  end

  def recovery_key
    recoveries.last.key if recoveries.any?
  end

  def unverify
    generate_token(:email_validation_hash)
  end

  def email_string
    "#{self} <#{self.email}>"
  end

  def self.admin_emails
    User.with_role(:superadmin).map(&:email)
  end

  # def coupon_code
  #   SecureRandom.urlsafe_base64[0..10].gsub(/[^0-9a-zA-Z]/i, '')
  # end

  def generate_fab10_coupon_code
    if self.fab10_coupon_code.blank?
      self.fab10_coupon_code = loop do
        random_token = SecureRandom.urlsafe_base64[0..10].gsub(/[^0-9a-zA-Z]/i, '')
        break random_token unless User.exists?(fab10_coupon_code: random_token)
      end
    end

    if employees.with_approved_state.any?
      self.fab10_cost = 35000
    end
  end

private

  def downcase_email
    self.email.downcase!
  end

end
