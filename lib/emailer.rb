require 'yaml'
require 'erb'
require 'net/smtp'
begin
  require 'smtp_tls'
rescue LoadError
end

class Emailer

  def initialize(project_path, recipient, from_address, from_alias, subject, text_message, html_diff, old_rev, new_rev, ref_name)
    config_file = File.join(File.dirname(THIS_FILE), '../config/email.yml')
    @config = YAML::load_file(config_file) if File.exist?(config_file)
    @config ||= {}
    @project_path = project_path
    @recipient = recipient
    @from_address = from_address
    @from_alias = from_alias
    @subject = subject
    @text_message = text_message
    @ref_name = ref_name
    @old_rev = old_rev
    @new_rev = new_rev

    template = File.join(File.dirname(__FILE__), '/../template/email.html.erb')
    @html_message = ERB.new(File.read(template)).result(binding)
  end

  def boundary
    return @boundary if @boundary
    srand
    seed = "#{rand(10000)}#{Time.now}"
    @boundary = Digest::SHA1.hexdigest(seed)
  end

  def stylesheet_string
    stylesheet = File.join(File.dirname(__FILE__), '/../template/styles.css')
    File.read(stylesheet)
  end

  def perform_delivery_smtp(content, smtp_settings)
    settings = { }
    %w(address port domain user_name password authentication use_tls).each do |key|
      val = smtp_settings[key].to_s.empty? ? nil : smtp_settings[key]
      settings.merge!({ key => val})
    end
    smtp = Net::SMTP.new settings['address'], settings['port']
    smtp.enable_starttls if settings['use_tls']
    smtp.start(settings['domain'], settings['user_name'], settings['password'], settings['authentication']) do |smtp|
      smtp.open_message_stream(@from_address, [@recipient]) do |f|
        content.each do |line|
          f.puts line
        end
      end
    end
  end

  def perform_delivery_sendmail(content, options = nil)
    sendmail_settings = {
      'location' => "/usr/sbin/sendmail",
      'arguments' => "-i -t"
    }.merge(options || {})
    command = "#{sendmail_settings['location']} #{sendmail_settings['arguments']}"
    IO.popen(command, "w+") do |f|
      f.write(content.join("\n"))
      f.flush
    end
  end

  def send
    from = @from_alias.empty? ? @from_address : "#{@from_alias} <#{@from_address}>"
    content = ["From: #{from}",
        "Reply-To: #{from}",
        "To: #{@recipient}",
        "Subject: #{@subject}",
        "X-Git-Refname: #{@ref_name}",
        "X-Git-Oldrev: #{@old_rev}",
        "X-Git-Newrev: #{@new_rev}",
        "Mime-Version: 1.0",
        "Content-Type: multipart/alternative; boundary=#{boundary}\n\n\n",
        "--#{boundary}",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Transfer-Encoding: 8bit",
        "Content-Disposition: inline\n\n\n",
        @text_message,
        "--#{boundary}",
        "Content-Type: text/html; charset=utf-8",
        "Content-Transfer-Encoding: 8bit",
        "Content-Disposition: inline\n\n\n",
        @html_message,
        "--#{boundary}--"]

    if @recipient.empty?
      puts content.join("\n")
      return
    end

    if @config['delivery_method'] == 'smtp'
      perform_delivery_smtp(content, @config['smtp_server'])
    else
      perform_delivery_sendmail(content, @config['sendmail_options'])
    end
  end

end
