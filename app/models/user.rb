=begin
RuckSack
-----------

Copyright (C) 2008 James S Urquhart (jamesu at gmail.com)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
=end

require 'digest/sha1'
require 'gd2' unless AppConfig.no_gd2

class User < ActiveRecord::Base
	include ActionController::UrlWriter
  
	belongs_to :account
	belongs_to :created_by, :class_name => 'User', :foreign_key => 'created_by_id'
	
	has_many :pages, :foreign_key => 'created_by_id', :dependent => :destroy
	has_and_belongs_to_many :shared_pages, :class_name => 'Page', :join_table => 'shared_pages'
	has_and_belongs_to_many :favourite_pages, :class_name => 'Page', :join_table => 'favourite_pages', :order => 'pages.title ASC'
	
	has_one :status, :dependent => :destroy
	has_many :journals, :order => 'created_at DESC', :dependent => :destroy
	
	has_many :reminders, :foreign_key => 'created_by_id', :order => 'at_time ASC', :dependent => :destroy do
		def done()
			find(:all, :conditions => ['at_time < ?', Time.now.utc])
		end
		def upcomming()
			find(:all, :conditions => ['at_time > ?', Time.now.utc])
		end
		def today(done=false)
		    current = Time.now.utc
		    if done
		      now = Time.utc(current.year, current.month, current.day)
		      now_until = current
		    else
		      now = Time.now
		      now_until = (now.to_date+1).to_time(:utc)
		    end
		    find(:all, :conditions => ["(at_time >= ? AND at_time < ?)", now, now_until])
		end
		def in_days(days)
		    day = Time.now.utc.to_date + days
		    find(:all, :conditions => ["(at_time >= ? AND at_time < ?)", day, day+1])
		end
		def in_month(month)
		    now = Time.now.utc
		    month = Time.utc(now.year, month).to_date
		    find(:all, :conditions => ["(at_time >= ? AND at_time < ?)", month, month>>1])
		end
		def in_months(months)
		    puts "in #{months} months"
		    month = Time.now.utc.to_date >> months
		    find(:all, :conditions => ["(at_time >= ? AND at_time < ?)", month, month>>1])
		end
		def on_after(time)
		    real_time = time.class == Date ? time.to_time(:utc) : time.utc
		    find(:all, :conditions => ["(at_time >= ?)", real_time])
		end
    end
    
	before_validation_on_create :process_create
	before_destroy :process_destroy
	
	def process_create
	   @cached_password ||= ''
	end
	
	def process_destroy
		# Explicitly remove these
		#ActiveRecord::Base.connection.execute("DELETE FROM project_users WHERE user_id = #{self.id}")
		#ActiveRecord::Base.connection.execute("DELETE FROM user_im_values WHERE user_id = #{self.id}")
		
		#FileRepo.handle_delete(self.avatar_file) unless self.avatar_file.nil?
	end
	
	def twister_array=(value)
		self.twister = value.join()
	end
	
	def twister_array()
		return self.twister.split('').map do |val|
			val.to_i
		end
	end
	
	def password=(value)
		salt = nil
		token = nil
		
		return if value.empty?
		
		if value.nil?
			self.salt = nil
			self.token = nil
			return
		end
		
		# Calculate a unique token with salt
		loop do
			# Grab a few random things...
			tnow = Time.now()
			sec = tnow.tv_usec
			usec = tnow.tv_usec % 0x100000
			rval = rand()
			roffs = rand(25)
			
			# Now we can calculate salt and token
			salt = Digest::SHA1.hexdigest(sprintf("%s%08x%05x%.8f", rand(32767), sec, usec, rval))[roffs..roffs+12]
			token = Digest::SHA1.hexdigest(salt + value)
			
			break if User.find(:first, :conditions => ["token = ?", token]).nil?
		end
		
		self.salt = salt
		self.token = token
		
		# Calculate string twist
		calc_twister = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']
		loop do
			calc_twister.sort! { rand(3)-1 }
			break if (calc_twister[0] != '0')
		end
		
		@cached_password = value.clone
		self.twister_array = calc_twister
	end
	
	def password
		@cached_password
	end
	
	def password_changed?
	    #puts "password_changed == " + ( !@cached_password.nil? ? 'yes' : 'no')
	    !@cached_password.nil?
	end
	
	def password_reset_key
	   Digest::SHA1.hexdigest(self.salt + self.twisted_token + (self.last_login.nil? ? '' : self.last_login.strftime('%Y-%m-%d %H:%M:%S')))
	end
	
	def twisted_token()
		value = self.token
		return value if not value.valid_hash?
		
		twist_array = self.twister_array
		result = ''
		(0..3).each { |i| offs = i*10; result += value[offs..(offs+9)].twist(twist_array) }
		
    	return result
	end
	
	def twisted_token_valid?(value)
		return false if not value.valid_hash?
		
		begin
		  twist_array = self.twister_array
		  result = ''
		  (0..3).each { |i| offs = i*10; result += value[offs..(offs+9)].untwist(twist_array) }
	    rescue
	       return false
		end
		
		return result == self.token
	end
	
	def self.openid_login(identity_url)
		user = find(:first, :conditions => ["identity_url = ?", identity_url])
		if (!user.nil?)
			now = Time.now.utc
			user.last_login = now
			user.last_activity = now
			user.last_visit = now
			user.save!
			return user
		else
			return nil
		end
	end
	
	def self.authenticate(login, pass)
		user = find(:first, :conditions => ["username = ?", login])
		if (!user.nil?) and (user.valid_password(pass))
			now = Time.now.utc
			user.last_login = now
			user.last_activity = now
			user.last_visit = now
			user.save!
			return user
		else
			return nil
		end
	end
	
	def valid_password(pass)
		return self.token == Digest::SHA1.hexdigest(self.salt + pass)
	end
	
	def send_password_reset()
		Notifier.deliver_password_reset(self)
	end
	
	def send_new_account_info(password=nil)
		Notifier.deliver_account_new_info(self, password)
	end
	
	def is_anonymous?
	  @is_anonymous
	end
	
	def is_anonymous=(value)
	  @is_anonymous = value
	end
	
	# Core permissions
	
	def self.can_be_created_by(user)
		return (user.member_of_owner? and user.is_admin)
	end
	
	def can_be_edited_by(user)
      return (self.id == user.id or (user.member_of_owner? and user.is_admin))
	end
	
	def can_be_deleted_by(user)
		return false if (self.owner_of_owner? or user.id == self.id)
		return user.is_admin
	end
	
	def can_be_seen_by(user)
		return (user.member_of_owner?)
	end
	
	# Specific permissions
    
	def can_add_favourite(user)
	  (user.is_admin or user.id == self.id) and !user.is_anonymous?
	end
	
	def pages_can_be_seen_by(user)
		user.is_admin or user.id == self.id
	end
	
	def reminders_can_be_seen_by(user)
		user.is_admin or user.id == self.id
	end
	
	def journals_can_be_seen_by(user)
		user.is_admin or user.id == self.id
	end
    
	# Helpers	
	def member_of_owner?
		!self.account_id.nil?
	end
	
	def owner_of_owner?
		self.account_id.nil? and Account.owner.id == self.account_id
	end
	
	def has_avatar?
	    !self.avatar_file.nil?
	end
		
	def avatar
		nil
	end
	
	def avatar=(value)
		return if AppConfig.no_gd2
		FileRepo.handle_delete(self.avatar_file) unless self.avatar_file.nil?
		
		if value.nil?
			self.avatar_file = nil
			return
		end
		
		content_type = value.content_type.chomp
		
		if !['image/jpg', 'image/jpeg', 'image/gif', 'image/png'].include?(content_type)
			self.errors.add(:avatar, "Unsupported format")
			return
		end
		
		max_width = AppConfig.max_avatar_width
		max_height = AppConfig.max_avatar_height
		
		begin
			data = value.read
			image = GD2::Image.load(data)
			image.resize!(image.width > max_width ? max_width : image.width,
			              image.height > max_height ? max_height : image.height)
		rescue
			self.errors.add(:avatar, "Invalid data")
			return
		end
		
		self.avatar_file = FileRepo.handle_storage(image.png)
	end
	
	def avatar_url
		self.avatar_file.nil? ? "/images/avatar.gif" : "/account/avatar/#{self.id}.png"
	end
 
  def display_name
    display_name? ? read_attribute(:display_name) : username
  end
	
	def object_name
		self.display_name
	end
	
	def object_url
		url_for :only_path => true, :controller => 'user', :action => 'card', :id => self.id
	end
	
	def self.get_online(active_in=15)
	  datetime = Time.now # Time.zone.now
	  datetime -= (active_in * 60)
	  
	  User.find(:all, :conditions => "last_activity > '#{datetime.strftime('%Y-%m-%d %H:%M:%S')}'", :select => "id, company_id, display_name")
	end
	
	def self.select_list
	   items = self.find(:all).collect do |user|
	     [user.username, user.id]
	   end
	   
	   items = [["None", 0]] + items
	end
	
	def self.owner
	   @@cached_owner ||= User.find(:first, :conditions => ['is_admin = ?', true])
	end
	    
	protected
	    
	before_create :process_params
	before_update :process_update_params
	 
	def process_params
		write_attribute("created_on", Time.now.utc)
		write_attribute("last_login", nil)
		write_attribute("last_activity", nil)
		write_attribute("last_visit", nil)
	end
	
	def process_update_params
		write_attribute("updated_on", Time.now.utc)
	end
	
	# Accesibility
	
	attr_accessible :display_name, :email, :time_zone, :title, :new_account_notification
	
	# Validation
	
	validates_presence_of :username, :on => :create
	validates_length_of :username, :within => 3..40
	
	validates_presence_of :password, :if => :password_changed?
	validates_length_of :password, :minimum => 4, :if => :password_changed?
	
	validates_confirmation_of :password, :if => :password_changed?
	
	validates_uniqueness_of :username
	validates_uniqueness_of :email
	validates_uniqueness_of :identity_url, :if => Proc.new { |user| !(user.identity_url.nil? or user.identity_url.empty? ) }
end
