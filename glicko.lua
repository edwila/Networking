--http://www.glicko.net/glicko/glicko2.pdf
local c = 173.7178 -- Used for conversion between Glicko1 and 2
local epsilon = 1e-6 -- Convergence

-- Shortcuts for commonly used math functions
local exp = math.exp
local sqrt = math.sqrt
local log = math.log

-- Glicko2
local Glicko2 = {
	Tau = 0.5, -- Slider for volatility
	InitialVolatility = 0.06
}; Glicko2.__index = Glicko2

-- Creates a Glicko rating with a specified version
function Glicko2.gv(Rating, RatingDeviation, Volatility, Version)
	local self = {
		Rating = Rating,
		RD = RatingDeviation,
		Vol = Volatility or Glicko2.InitialVolatility,
		Version = Version or 2,
	}

	return setmetatable(self, Glicko2)
end

-- Creates a Glicko2 rating
function Glicko2.g1(Rating, RatingDeviation, Volatility)
	return Glicko2.gv(
		Rating or 1500,
		RatingDeviation or 350,
		Volatility,
		1
	)
end

-- Creates a Glicko1 rating
function Glicko2.g2(Rating, RatingDeviation, Volatility)
	return Glicko2.gv(
		Rating or 0,
		RatingDeviation or 350/c,
		Volatility,
		2
	)
end

function Glicko2:copy()
	return Glicko2.gv(self.Rating, self.RD, self.Vol, self.Version)
end

-- Scales glicko rating to Glicko2
function Glicko2:to2()
	if self.Version == 2 then
		return self:copy()
	end

	local g2 = Glicko2.g2((self.Rating - 1500)/c, self.RD/c, self.Vol)

	if self.Score then
		g2.Score = self.Score
	end

	return g2
end

-- Scales glicko rating to Glicko1
function Glicko2:to1()
	if self.Version == 1 then
		return self:copy()
	end

	local g2 = Glicko2.g2(self.Rating*c + 1500, self.RD*c, self.Vol)

	if self.Score then
		g2.Score = self.Score
	end

	return g2
end

function Glicko2.serialize(gv)
	return {
		gv.Rating,
		gv.RD,
		gv.Vol,
		gv.Score
	}
end

function Glicko2.deserialize(gv_s, version)
	local constructor = nil

	-- Finds glicko constructor for specified version
	if version == 1 then
		constructor = Glicko2.g1
	elseif version == 2 then
		constructor = Glicko2.g2
	else
		error("Version must be specified for deserialization", 2)
	end

	local gv = constructor(gv_s[1], gv_s[2], gv_s[3])

	-- Inserts a score if there is one
	if gv_s[4] then
		gv = gv:score(gv_s[4])
	end

	return gv
end

-- Attaches a score to an opponent
function Glicko2:score(score)
	local new_g2 = self:copy()

	--lost: 0, win: 1, tie: 0.5
	new_g2.Score = score or 0

	return new_g2
end

-- Function g as described in step 3
local function g(RD)
	return 1/sqrt(1 + 3*RD^2/math.pi^2)
end

-- Function E as described in step 3
local function E(rating, opRating, opRD)
	return 1/(1 + exp(-g(opRD)*(rating - opRating)))
end

-- Constructor for function f described in step 5
local function makebigf(g2, v, delta)
	local a = log(g2.Vol^2)

	return function(x)
		local numer = exp(x)*(delta^2 - g2.RD^2 - v - exp(x)) --numerator
		local denom = 2*(g2.RD^2 + v + exp(x))^2 --denominator
		local endTerm = (x - a)/(Glicko2.Tau^2) --final term

		return numer/denom - endTerm
	end
end

-- Updates a Glicko rating using the last set of matches
function Glicko2:update(matches)
	local g2 = self
	local originalVersion = g2.Version

	-- convert ratings to glicko2
	if originalVersion == 1 then
		g2 = g2:to2()
	end

	for i, match in ipairs(matches) do
		if match.Version == 1 then
			matches[i] = match:to2()
		end
	end

	-- step 3: compute v
	local v = 0

	for j, match in ipairs(matches) do
		local EValue = E(g2.Rating, match.Rating, match.RD)

		v = v + g(match.RD)^2*EValue*(1 - EValue)
	end

	v = 1/v

	-- step 4: compute delta
	local delta = 0

	for j, match in ipairs(matches) do
		local EValue = E(g2.Rating, match.Rating, match.RD)

		delta = delta + g(match.RD)*(match.Score - EValue)
	end

	delta = delta*v

	-- step 5: find new volatility (iterative process)
	local a = log(g2.Vol^2)

	local bigf = makebigf(g2, v, delta)

	-- step 5.2: find initial A and B values
	local A = a
	local B = 0

	if delta^2 > g2.RD^2 + v then
		B = log(delta^2 - g2.RD^2 - v)
	else
		--iterative process for solving B
		local k = 1

		while bigf(a - k*Glicko2.Tau) < 0 do
			k = k + 1
		end

		B = a - k*Glicko2.Tau
	end

	-- step 5.3: compute values of bigf of A and B
	local fA = bigf(A)
	local fB = bigf(B)

	-- step 5.4: iterates until A and B converge
	while math.abs(B - A) > epsilon do
		local C = A + (A - B)*fA/(fB - fA)
		local fC = bigf(C)

		if fC*fB < 0 then
			A = B
			fA = fB
		else
			fA = fA/2
		end

		B = C
		fB = fC
	end

	-- step 5.5: set new volatility
	local newVol = g2.Vol

	if #matches > 0 then
		newVol = exp(A/2)
	end

	-- step 6: compute new rating and RD
	local newRD = sqrt(g2.RD^2 + newVol^2)
	local newRating = g2.Rating

	if #matches > 0 then
		newRD = 1/sqrt(1/newRD^2 + 1/v)
		newRating = 0

		for j, match in ipairs(matches) do
			local EValue = E(g2.Rating, match.Rating, match.RD)
			newRating = newRating + g(match.RD)*(match.Score - EValue)
		end

		newRating = g2.Rating + newRD^2*newRating
	end

	--wrap up results
	local result = Glicko2.g2(newRating, newRD, newVol)

	if originalVersion == 1 then
		result = result:to1()
	end

	return result
end

function Glicko2:deviation(deviations)
	deviations = deviations or 2
	local radius = self.RD*deviations

	return self.Rating - radius, self.Rating + radius
end


function Glicko2:range(padding)
	padding = padding or 0
	local small, big = self:deviation()

	return small - padding, big + padding
end

function Glicko2:percent(confidence)
	confidence = math.clamp(confidence, 0, 1)
	assert(confidence < 1, "Percentage cannot be equal or greater than 1")

	--This is a simple inverse erf approximation, has accuracy of +- 0.02
	return self:deviation(.5877*math.log((1 + confidence)/(1 - confidence)))
end
return Glicko
