include("setup.jl")

@testset "ca_roots" begin
    withenv(
        "JULIA_SSL_CA_ROOTS_PATH" => nothing,
    ) do
        @test ca_roots_path() isa String
        @test ispath(ca_roots_path())
        if Sys.iswindows() || Sys.isapple()
            @test ca_roots_path() == BUNDLED_CA_ROOTS
            @test ca_roots() === nothing
        else
            @test ca_roots_path() != BUNDLED_CA_ROOTS
            @test ca_roots() == ca_roots_path()
        end
        unset = ca_roots(), ca_roots_path()
        value = "Why hello!"
        ENV["JULIA_SSL_CA_ROOTS_PATH"] = value
        @test ca_roots() == value
        @test ca_roots_path() == value
        ENV["JULIA_SSL_CA_ROOTS_PATH"] = ""
        @test ca_roots() == unset[1]
        @test ca_roots_path() == unset[2]
    end
end

@testset "verify_host" begin
    withenv(
        "JULIA_NO_VERIFY_HOSTS" => nothing,
        "JULIA_SSL_NO_VERIFY_HOSTS" => nothing,
        "JULIA_SSH_NO_VERIFY_HOSTS" => nothing,
    ) do
        @testset "verify everything" begin
            for url in TEST_URLS
                @test verify_host(url) # cover this API once
                for transport in (nothing, "ssl", "ssh", "xyz")
                    @test verify_host(url, transport)
                end
            end
            clear_vars!(ENV)
        end

        @testset "bad patterns fail safely" begin
            patterns = [
                "~", "* *", "*~*", "***", "∀", "~, ***",
                ".com", "*com", ".*com", ".example.com", "*example.com",
            ]
            for pattern in patterns
                ENV["JULIA_NO_VERIFY_HOSTS"] = pattern
                for url in TEST_URLS, transport in TRANSPORTS
                    verify = without_warnings() do
                        verify_host(url, transport)
                    end
                    @test verify
                end
            end
            clear_vars!(ENV)
        end

        @testset "only ignore bad patterns in list" begin
            patterns = ["ok.com,~", "^, ok.com ,, !"]
            for pattern in patterns
                ENV["JULIA_NO_VERIFY_HOSTS"] = pattern
                for url in TEST_URLS
                    verify = without_warnings() do
                        verify_host(url)
                    end
                    @test verify
                end
                verify = without_warnings() do
                    verify_host("ok.com")
                end
                @test !verify
        end
            clear_vars!(ENV)
        end

        @testset "verify nothing" begin
            for pattern in ["**", "example.com,**", "**,, blah"]
                ENV["JULIA_NO_VERIFY_HOSTS"] = pattern
                for url in TEST_URLS, transport in TRANSPORTS
                    @test !verify_host(url, transport)
                end
            end
            clear_vars!(ENV)
        end

        @testset "SSL no verify" begin
            for pattern in ["**", "example.com,**", "**, blah"]
                ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = pattern
                for url in TEST_URLS, transport in TRANSPORTS
                    no_verify = transport in ["ssl", "tls"]
                    @test verify_host(url, transport) == !no_verify
                end
            end
            clear_vars!(ENV)
        end

        @testset "SSH no verify" begin
            for pattern in ["**", "example.com,**", "**, blah"]
                ENV["JULIA_SSH_NO_VERIFY_HOSTS"] = pattern
                for url in TEST_URLS, transport in TRANSPORTS
                    no_verify = transport == "ssh"
                    @test verify_host(url, transport) == !no_verify
                end
            end
            clear_vars!(ENV)
        end

        @testset "complex scenario" begin
            ENV["JULIA_NO_VERIFY_HOSTS"] = "**.safe.example.com"
            ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = "ssl.example.com"
            ENV["JULIA_SSH_NO_VERIFY_HOSTS"] = "ssh.example.com,*.ssh.example.com"
            for transport in TRANSPORTS
                for url in TEST_URLS
                    @test verify_host(url, transport)
                end
                hosts = [
                    "safe.example.com",
                    "api.SAFE.example.COM",
                    "v1.API.safe.eXample.com",
                ]
                for host in hosts, (url, valid) in host_variants(host)
                    @test verify_host(url, transport) == !valid
                end
                hosts = [
                    "ssl.example.com",
                    "SSL.example.com",
                    "ssl.Example.COM",
                ]
                for host in hosts, (url, valid) in host_variants(host)
                    no_verify = valid && transport in ["ssl", "tls"]
                    @test verify_host(url, transport) == !no_verify
                end
                hosts = [
                    "sub.ssl.example.com",
                    "sub.SSL.example.com",
                    "ssl..example.com",
                ]
                for host in hosts, (url, valid) in host_variants(host)
                    @test verify_host(url, transport)
                end
                hosts = [
                    "ssh.example.com",
                    "ssh.EXAMPLE.com",
                    "sub.ssh.example.com",
                    "sub.ssh.example.COM",
                ]
                for host in hosts, (url, valid) in host_variants(host)
                    no_verify = valid && transport == "ssh"
                    @test verify_host(url, transport) == !no_verify
                end
                hosts = [
                    "v1.api.ssh.example.com",
                    "123.api.SSH.example.COM",
                ]
                for host in hosts, (url, valid) in host_variants(host)
                    @test verify_host(url, transport)
                end
            end
            clear_vars!(ENV)
        end
    end
end
