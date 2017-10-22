require 'openssl'
require 'fileutils'
require 'acme-client'

class AcmeAgent

    WEB_DOC_ROOT = "/ssl-agent/webserver-root"
    CERTS_DIR = "/ssl-agent/certs"

    FILE_NAMES = {
        cert_chain: "cert_chain.pem",
        cert_server: "cert_server.pem",
        cert_fullchain: ENV['OBTAINED_CERT_FILENAME'] || 'cert_fullchain.pem',
        cert_private: ENV['CERT_PRIVATE_KEY_FILENAME'] || 'cert_private_key.pem',
        acct_private: ENV['ACCT_PRIVATE_KEY_FILENAME'] || 'acct_private_key.pem'
    }

    def initialize(contact_email, cert_env, domain_names=[])
        @domain_names = domain_names
        @contact_email = contact_email
        @cert_env = cert_env
        @private_keys = { account: nil, certificate: nil }
    end

    def create
        print_env
        register
        verify_domains
        backup_certs
        generate_certs
        print_summary
    end

    def renew
        print_env
        load_private_keys
        verify_domains
        backup_certs
        generate_certs
        print_summary
    end

    def info
        print_env
        print_summary false
    end
    
    # def revoke
    #     puts "Revoke - Implementation pending"
    # end
    
    private
    
    def acme_client
        @acme_client ||= Acme::Client.new({
            private_key: private_key(:account),
            endpoint: api_endpoint,
            connection_options: { request: { open_timeout: 8, timeout: 8 } }
        })
    end

    def api_endpoint
        @api_endpoint ||= "https://acme-#{@cert_env == 'prod' ? 'v01' : 'staging'}.api.letsencrypt.org/"
    end

    def print_env
        print_heading("Environment")
        puts "API Endpoint: #{api_endpoint}"
    end    

    def register
        print_heading "Register with LetsEncrypt"
        acme_client.register(contact: "mailto:#{@contact_email}").agree_terms
    rescue
        puts "\nSorry! something went wrong registering with key. You might want to try with a new private key or delete the private key file and let me generate a new private key. Error: [#{$!}]"
        puts "Or .. may be you're trying renew with an existing private key?"
        print_usage true
    end

    def load_private_keys
        print_heading "Use existing private keys"
        @private_keys.keys.each { |key_type| load_private_key(key_type) }
    end

    def verify_domains
        print_heading "Verify Domain Authorization"
        @domain_names.each do |domain_name|
            verify_domain(domain_name)
        end
    end

    def backup_certs
        print_heading "Backup Cert & Keys"
        backup_dir = File.join(CERTS_DIR, "certs_#{Time.now.to_i}")
        puts "Backup to: #{backup_dir}"
        FileUtils.mkdir_p(backup_dir)
        %w(pem crt key der).each do |type| 
            FileUtils.cp_r(Dir.glob("#{CERTS_DIR}/*.#{type}"), "#{backup_dir}/")
        end
    rescue
        puts "Failed to backup old cert files: #{$!}"
    end

    def generate_certs
        print_heading "Obtain & Create Cert"
        csr = Acme::Client::CertificateRequest.new(names: @domain_names, private_key: private_key(:certificate))
        certificate = acme_client.new_certificate(csr)

        puts "Write certs to files"
        write_cert_file(FILE_NAMES[:cert_chain], certificate.chain_to_pem)
        write_cert_file(FILE_NAMES[:cert_server], certificate.to_pem)
        write_cert_file(FILE_NAMES[:cert_fullchain], certificate.fullchain_to_pem)
    end

    def print_summary(add_notes=true)
        print_heading "Summary"

        puts "Account / Registration info"
        puts "\tPrivate Key:         #{filename_and_status(:acct_private)}"

        puts "\nSSL Certificate files"
        puts "\tSSL Certificate Key: #{filename_and_status(:cert_private)}"
        puts "\tSSL Certificate:     #{filename_and_status(:cert_fullchain)}"

        puts "\nOther files"
        puts "\tChain:               #{filename_and_status(:cert_chain)}"
        puts "\tCert without chain:  #{filename_and_status(:cert_server)}"

        if add_notes
            print_heading "Notes"
            puts "- Save both private key files which will be required during renewal"
            puts "- If you need to create new private keys, delete the private keys from certs folder before executing CREATE again"
        end
    end

    # key_type = :account | :certificates
    def private_key(key_type = :account)
        return @private_keys[key_type] unless @private_keys[key_type].nil?
        private_key_exist?(key_type) ? load_private_key(key_type) : gen_private_key(key_type)
        @private_keys[key_type]
    end

    def private_key_filename(key_type = :account)
        FILE_NAMES[ "#{key_type == :account ? 'acct' : 'cert'}_private".to_sym ]
    end

    def load_private_key(key_type = :account)
        puts "Loading existing #{key_type} private key."
        unless private_key_exist?(key_type)
            puts "#{key_type.upcase} private key not found at: #{file_path(private_key_filename(key_type))}"
            print_usage true
        end
        @private_keys[key_type] = OpenSSL::PKey::RSA.new(read_cert_file(private_key_filename(key_type)))
    rescue
        puts "\nFailed to load #{key_type} private key. Error: [#{$!}]"
        print_usage true
    end

    def gen_private_key(key_type = :account)
        puts "Generate a new #{key_type.upcase} private key"
        @private_keys[key_type] = OpenSSL::PKey::RSA.new(4096)
        write_cert_file(private_key_filename(key_type), @private_keys[key_type].to_pem)
    end

    def verify_domain(domain_name)
        puts "Authorization of domain '#{domain_name}'"
        
        authorization = acme_client.authorize(domain: domain_name)
        puts "Domain Verification status: #{authorization.status}"
    
        if authorization.status == 'valid' # possible renewal request
            puts "Skip domain verification"
        else
            challenge = authorization.http01
            write_challenge_file(challenge)
            puts "Domain Verification URL: http://#{domain_name}/#{challenge.filename}"
    
            request_verification(authorization) # returns pending|valid|invalid            
        end
    end

    def write_challenge_file(challenge)        
        puts "Creating challenge file under web doc root - '#{challenge.filename}'"
        abs_file_path = File.join( WEB_DOC_ROOT, challenge.filename)
        FileUtils.mkdir_p(File.dirname(abs_file_path))
        File.write( abs_file_path, challenge.file_content )
        File.chmod( 0644, abs_file_path ) # to avoid file permissions for nginx/apache to serve this file
    end

    def request_verification(domain_authorization)
        puts "Requesting verification - #{domain_authorization.uri}"
        challenge = acme_client.fetch_authorization(domain_authorization.uri).http01
        challenge.request_verification

        3.times do |i|
            puts "Attempt #{i+1}, Wait 3 seconds ..."
            sleep(3)
            v_status = challenge.authorization.verify_status
            puts "Domain Verification status: #{v_status}\n"
            break if v_status == 'valid' or v_status == 'invalid' # pending can wait - raise some error
        end

        challenge.authorization.verify_status
    end

    def write_cert_file(name, content)
        f_path = file_path(name)
        puts "\tCreating #{f_path}"
        File.write(f_path, content)
    end

    def read_cert_file(name)
        f_path = file_path(name)
        puts "\tReading file #{f_path}"
        File.read(f_path)
    end

    def file_path(name)
        File.join(CERTS_DIR, name)
    end

    def cert_file_exist?(name)
        File.exist? file_path(name)
    end

    def private_key_exist?(key_type = :account)
        cert_file_exist?(private_key_filename(key_type))
    end

    def print_heading(h='---')
        s = " #{h.upcase} "
        puts "\n#{s.center(80, '=')}\n\n"
    end

    def print_usage(exitt=false)
        print_heading "Usage"
        puts "docker-compose run --rm <SERVICE NAME> info|create|renew"
        puts "\n -- OR -- \n\n"
        puts "docker run -it -e LETSENCRYPT_ENV=staging -e DOMAIN_NAMES=YOURDOMAIN.COM \\\n -e CONTACT_EMAIL=YOURMEMAIL@DOMAIN.COMM \\\n -v \"<NGINX ROOT ON DOCKER HOST>:/ssl-agent/webserver-root:rw\" \\\n -v \"<DIRECTORY FOR CERTS & KEYS>:/ssl-agent/certs:rw\" \\\n devteds/ssl-agent:latest  info|create|renew"
        puts "\n"        
        
        print_summary(add_notes=false)

        exit 1 if exitt
    end

    def filename_and_status(key)
        "#{FILE_NAMES[key]} (#{cert_file_exist?(FILE_NAMES[key]) ? 'Found' : 'Not found'})"
    end
end

domain_names = ENV['DOMAIN_NAMES'].split(",").map(&:strip)
agent = AcmeAgent.new(ENV['CONTACT_EMAIL'], ENV['LETSENCRYPT_ENV'] || 'staging', domain_names)

action = (ARGV.first || "").strip
unless %(info create renew).include?(action)
    puts "ERROR: command invalid. Should be one of 'info,create,renew'"
    exit 1
end

agent.send(action.to_sym)

puts "\n\nAll done"
