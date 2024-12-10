local shell = require("shell")

local function pow(x, y) return x^y end

local function binomial_coeff(n, k)
  if (k > n-k) then
    k = n-k
  end

  if (k == 0 or k == n) then
    return 1
  end

  local res = 1
  for i = 1, k do
    res = res*(n-i+1)/i
  end
  return res
end

local function acc_fun(x_0, x_n, fun, ...)
  local acc = 0
  for i = x_0, x_n do
    acc = acc + fun(i, ...)
  end
  return acc
end

local function binom_neg(x, k, p) -- P(X = x), X >= k
  return binomial_coeff(x-1, k-1)*pow(p, k)*pow(1-p, x-k)
end

local function binom_neg_acc(x, k, p) -- P(X <= x), X >= k
  return acc_fun(x, k, binom_neg, x, p)
end

local function greg_chance(total, required, chance)
  return string.format("%.2f%%", binom_neg_acc(required, total, chance)*100)
end

local function tostacks(x) return x*64 end

-- I have a dust that can be obtained by macerating a funny stone with a 5% chance
-- What are the chances of getting 1 stack of dusts, if i macerate
-- up to 20 stacks of funny stones?
-- print(greg_chance(tostacks(20), tostacks(1), 0.05)) -- ~ 51.79%

local args, _ = shell.parse(...)

-- $ gregchance 20 64 0.05
local total = tostacks(args[1])
local req = args[2]
local prob = args[3]

print(greg_chance(total, req, prob))
