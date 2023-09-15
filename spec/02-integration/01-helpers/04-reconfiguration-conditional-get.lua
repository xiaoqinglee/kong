local helpers = require "spec.helpers"


describe("configuration conditional get", function()
    lazy_setup(function()
        helpers.get_db_utils(nil, {}) -- runs migrations
        assert(helpers.start_kong(env))
    end)

    lazy_teardown(function()
        helpers.stop_kong()
    end)

    local proxy_client
    local admin_client

    before_each(function()
        proxy_client = helpers.proxy_client(5000)
        admin_client = helpers.admin_client(10000)
    end)

    after_each(function()
        if proxy_client then
            proxy_client:close()
        end
        if admin_client then
            admin_client:close()
        end
    end)

    it("waits until a change through the admin API has propagated to the proxy path", function()
        local res = admin_client:post(
                "/services",
                {
                    body = {
                        protocol = "http",
                        name     = "foo",
                        host     = "127.0.0.1",
                    },
                    headers = { ["Content-Type"] = "application/json" },
                })
        assert.res_status(201, res)
        res = admin_client:post(
                "/services/foo/routes",
                {
                    body = {
                        paths = {"/blub"}
                    },
                    headers = { ["Content-Type"] = "application/json" },
                })
        assert.res_status(201, res)
        local date = res.headers['Date']
        -- flaky test below - we can't be sure that the configuration did not happen quicker than expected
        res = proxy_client:get(
                "/",
                { headers = { ["X-Kong-If-Reconfigured-Since"] = date } }
        )
        assert.res_status(503, res)
        assert
                .with_timeout(30)
                .eventually(
                function()
                    local client = helpers.proxy_client()
                    local res = client:get(
                            "/nonexistent",
                            { headers = { ["X-Kong-If-Reconfigured-Since"] = date } }
                    )
                    client:close()
                    return res.status == 404
                end)
                .is_truthy()
    end)
end)
