#==
# Copyright (C) 2008 James S Urquhart
# Portions Copyright (C) 2009 Qiushi He
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#++

class AlbumPicture < ActiveRecord::Base
  belongs_to :album
  def page; self.album.page; end
  def page_id; self.album.page_id; end

  has_many :application_logs, :as => :rel_object, :dependent => :nullify
  
  has_attached_file :picture, :styles => { :album => "150x150#" },
			      :url => '/pages/:page_id/albums/:album_id/pictures/:id/:style.:extension',
			      :path => ':rails_root/assets/:class/:id_partition/:style/:basename.:extension'
  
  belongs_to :created_by, :class_name => 'User', :foreign_key => 'created_by_id'
  belongs_to :updated_by, :class_name => 'User', :foreign_key => 'updated_by_id'

  searchable do
    text :caption
  end

  after_create   :process_create
  before_update  :process_update_params
  before_destroy :process_destroy

  def process_create
    ApplicationLog.new_log(self, self.created_by, :add)
  end

  def process_update_params
    ApplicationLog.new_log(self, self.updated_by, :edit)
  end

  def process_destroy
    ApplicationLog.new_log(self, self.updated_by, :delete)
  end

  def object_name
    self.caption? ? self.caption : self.picture.original_filename
  end

  def set_position(value, user=nil)
    self.position = value
    self.updated_by = user unless user.nil?
  end

  # Common permissions

  def self.can_be_created_by(user, in_album)
    in_album.picture_can_be_added_by(user)
  end

  def can_be_edited_by(user)
    album.can_be_edited_by(user)
  end

  def can_be_deleted_by(user)
    album.can_be_deleted_by(user)
  end

  def can_be_seen_by(user)
    album.can_be_seen_by(user)
  end

  attr_accessible :caption, :picture

  # Validation

  validates_attachment_presence :picture
end
