import { voteRouterParamsSchema } from "~/schemas/polls";
import { getServerAuthSession } from "~/server/auth";
import fetch from "~/server/fetch";

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig();

  const routerParams = await getValidatedRouterParams(
    event,
    voteRouterParamsSchema(config.public).safeParse,
  );

  if (!routerParams.success) {
    throw createError({
      statusCode: 400,
      message: routerParams.error.message,
    });
  }

  const session = await getServerAuthSession(event);
  const result = await fetch.POST(
    session
      ? "/polls/{pollId}/{optionId}"
      : "/public/polls/{pollId}/{optionId}",
    {
      params: {
        path: routerParams.data,
      },
      headers: session
        ? { Authorization: `Bearer ${session.user.idToken}` }
        : {},
    },
  );
  if (result.error) {
    throw createError({});
  }

  return result.data;
});
